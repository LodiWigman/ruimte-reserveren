-- Existing case IDs and reservation data are retained.
BEGIN;

-- Availability checks intentionally do not require an organisation.
-- Enforce it where rows are written, across booking, request, admin and import flows.
CREATE FUNCTION han_private.require_item_organization() RETURNS trigger
LANGUAGE plpgsql SET search_path='' AS $$
BEGIN
  IF NEW.organization IS NULL OR NEW.organization ~ '^[[:space:]]*$' THEN
    -- Keep old rows editable by unrelated operations such as ownership transfer.
    IF TG_OP='UPDATE' THEN
      IF NEW.organization IS NOT DISTINCT FROM OLD.organization THEN RETURN NEW; END IF;
    END IF;
    RAISE EXCEPTION 'Organisatie/afdeling is verplicht.';
  END IF;
  RETURN NEW;
END;
$$;
REVOKE ALL ON FUNCTION han_private.require_item_organization() FROM PUBLIC,anon,authenticated;
CREATE TRIGGER require_item_organization BEFORE INSERT OR UPDATE OF organization ON public.reserveringen
FOR EACH ROW EXECUTE FUNCTION han_private.require_item_organization();
CREATE TRIGGER require_item_organization BEFORE INSERT OR UPDATE OF organization ON public.reserveringsverzoeken
FOR EACH ROW EXECUTE FUNCTION han_private.require_item_organization();

CREATE OR REPLACE FUNCTION public.han_occupancy(from_date date,to_date date) RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path='' AS $$
DECLARE u text:=han_private.require_user(); admin boolean:=han_private.role()='admin'; result jsonb;
BEGIN
  IF from_date IS NULL OR to_date IS NULL OR to_date<from_date OR to_date-from_date>31 THEN
    RAISE EXCEPTION 'Kies maximaal 32 dagen';
  END IF;
  SELECT coalesce(jsonb_agg(x),'[]'::jsonb) INTO result FROM (
    SELECT CASE WHEN user_id=u OR admin THEN id END AS id,user_id=u AS mine,
      room_id,date,start_time,end_time,'confirmed'::text AS status,
      CASE WHEN user_id=u OR admin THEN name END AS name,
      CASE WHEN user_id=u OR han_private.role() IN ('intern','admin') THEN organization END AS organization
    FROM public.reserveringen WHERE date BETWEEN from_date AND to_date
    UNION ALL
    SELECT CASE WHEN user_id=u OR admin THEN id END,user_id=u,
      room_id,date,start_time,end_time,'pending',
      CASE WHEN user_id=u OR admin THEN name END,
      CASE WHEN user_id=u OR han_private.role() IN ('intern','admin') THEN organization END
    FROM public.reserveringsverzoeken WHERE status='pending' AND date BETWEEN from_date AND to_date
  ) x;
  IF jsonb_array_length(result)>20000 THEN RAISE EXCEPTION 'Te veel gegevens; kies een kortere periode'; END IF;
  RETURN result;
END;
$$;

CREATE OR REPLACE FUNCTION public.han_manage_case(item_id uuid,expected_version bigint,new_status text,category text,action text DEFAULT 'save') RETURNS integer
LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE c han_private.support_messages;
BEGIN
  PERFORM han_private.write_lock(); PERFORM han_private.require_admin(); c=han_private.case_access(item_id);
  IF c.version IS DISTINCT FROM expected_version THEN RAISE EXCEPTION 'STALE_ITEM'; END IF;
  IF action IS NULL OR action NOT IN ('save','archive','reopen') THEN RAISE EXCEPTION 'ACTION_INVALID'; END IF;
  IF category IS NULL OR category NOT IN ('question','complaint','tip','unclassified') OR new_status IS NULL OR new_status NOT IN ('open','in_behandeling','afgehandeld') THEN RAISE EXCEPTION 'STATUS_INVALID'; END IF;
  IF action='archive' AND (c.status<>'afgehandeld' OR c.archived_at IS NOT NULL) THEN RAISE EXCEPTION 'ARCHIVE_RESOLVED_ONLY'; END IF;
  IF c.archived_at IS NOT NULL AND action<>'reopen' THEN RAISE EXCEPTION 'CASE_ARCHIVED'; END IF;
  UPDATE han_private.support_messages SET category=han_manage_case.category,
    status=CASE WHEN action='reopen' THEN 'open' WHEN action='archive' THEN 'afgehandeld' ELSE new_status END,
    archived_at=CASE WHEN action='archive' THEN now() WHEN action='reopen' THEN NULL ELSE archived_at END,
    handled_by=han_private.uid(),handled_at=now(),version=version+1 WHERE id=item_id;
  IF action='archive' THEN
    -- Archive and notification commit together. The version check above rejects retries.
    -- Notify even when the administrator is also the submitter.
    INSERT INTO han_private.notifications(recipient_id,event_id,event_type,item_kind,item_id,details)
    VALUES(c.user_id,gen_random_uuid(),'case_archived','case',item_id,
      jsonb_build_object('category',category,'case_id',item_id,'version',c.version+1));
  END IF;
  RETURN 1;
END;
$$;

COMMIT;
