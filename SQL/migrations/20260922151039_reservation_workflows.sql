-- Gerichte wijziging op de Clerk-basis; geen reset. Uitvoeren in één transactie.
DO $workflow_migration$ BEGIN
ALTER TABLE public.reserveringen
  ADD COLUMN organization text CHECK (char_length(organization)<=120),
  ADD COLUMN occasion text CHECK (char_length(occasion)<=120),
  ADD COLUMN motivation text CHECK (char_length(motivation)<=500);
ALTER TABLE public.role_requests ADD COLUMN requested_role text NOT NULL DEFAULT 'intern'
  CHECK (requested_role IN ('intern','admin'));

-- Alleen eenduidige koppelingen aanvullen; geen organisatorgegevens verzinnen.
WITH matches AS (
  SELECT b.id,min(q.organization) AS organization,min(q.occasion) AS occasion,min(q.motivation) AS motivation
  FROM public.reserveringen b JOIN public.reserveringsverzoeken q
    ON q.status='approved' AND q.user_id=b.user_id AND q.room_id=b.room_id
    AND q.date=b.date AND q.start_time=b.start_time AND q.end_time=b.end_time
    AND q.recurrence_id IS NOT DISTINCT FROM b.recurrence_id
  GROUP BY b.id HAVING count(*)=1
)
UPDATE public.reserveringen b SET organization=m.organization,occasion=m.occasion,motivation=m.motivation
FROM matches m WHERE b.id=m.id;
DELETE FROM public.reserveringsverzoeken WHERE status='approved';

DROP FUNCTION public.han_role_request(text,text,text);
CREATE OR REPLACE FUNCTION han_private.validate_item(item jsonb, external_request boolean DEFAULT false)
RETURNS void LANGUAGE plpgsql SET search_path='' AS $$
DECLARE d date; s time; e time;
BEGIN
  IF jsonb_typeof(item) IS DISTINCT FROM 'object' THEN RAISE EXCEPTION 'Ongeldige reserveringsgegevens'; END IF;
  IF coalesce(item->>'date','') !~ '^\d{4}-\d{2}-\d{2}$'
     OR coalesce(item->>'start_time','') !~ '^([01]\d|2[0-3]):[0-5]\d$'
     OR coalesce(item->>'end_time','') !~ '^([01]\d|2[0-3]):[0-5]\d$' THEN
    RAISE EXCEPTION 'Gebruik een geldige datum en tijden op hele minuten';
  END IF;
  d=(item->>'date')::date; s=(item->>'start_time')::time; e=(item->>'end_time')::time;
  IF d < (now() AT TIME ZONE 'Europe/Amsterdam')::date OR d > DATE '2100-12-31' OR s>=e THEN
    RAISE EXCEPTION 'Datum ligt in het verleden of eindtijd ligt niet na begintijd';
  END IF;
  -- Niet-bestaande en dubbele lokale kloktijden rond de DST-overgang afwijzen.
  -- De app reserveert fysieke ruimtes op Nederlandse lokale kloktijd.
  IF EXISTS (SELECT 1 FROM (VALUES(d+s),(d+e)) v(t) WHERE
      (v.t AT TIME ZONE 'Europe/Amsterdam') AT TIME ZONE 'Europe/Amsterdam' <> v.t
      OR ((v.t AT TIME ZONE 'Europe/Amsterdam')-interval '1 hour') AT TIME ZONE 'Europe/Amsterdam'=v.t
      OR ((v.t AT TIME ZONE 'Europe/Amsterdam')+interval '1 hour') AT TIME ZONE 'Europe/Amsterdam'=v.t) THEN
    RAISE EXCEPTION 'Niet-bestaande of dubbele Nederlandse kloktijd bij zomer-/wintertijd';
  END IF;
  IF NOT EXISTS(SELECT 1 FROM public.rooms WHERE id=item->>'room_id' AND active) THEN RAISE EXCEPTION 'Ruimte onbekend of inactief'; END IF;
  IF external_request AND (nullif(btrim(item->>'organization'),'') IS NULL OR nullif(btrim(item->>'occasion'),'') IS NULL) THEN
    RAISE EXCEPTION 'Organisatie/afdeling en gelegenheid zijn verplicht voor externen';
  END IF;
END;
$$;

CREATE OR REPLACE FUNCTION han_private.add_booking(item jsonb, owner_id text, series_id uuid) RETURNS uuid
LANGUAGE plpgsql SET search_path='' AS $$
DECLARE result uuid;
BEGIN
  INSERT INTO public.reserveringen(user_id,name,room_id,date,start_time,end_time,persons,description,recurrence_id,organization,occasion,motivation)
  VALUES(owner_id,item->>'name',item->>'room_id',(item->>'date')::date,(item->>'start_time')::time,(item->>'end_time')::time,
    (item->>'persons')::integer,item->>'description',series_id,item->>'organization',item->>'occasion',item->>'motivation') RETURNING id INTO result;
  RETURN result;
END;
$$;

CREATE OR REPLACE FUNCTION public.han_edit(kind text,item_id uuid,scope text,item jsonb,convert_to_request boolean DEFAULT false) RETURNS integer
LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE ids uuid[]; first_row record; r record; next_item jsonb; delta int; series_id uuid; affected int:=0; u text:=han_private.require_user(); needs_request boolean:=false; request_ids uuid[]:='{}';
BEGIN
  PERFORM han_private.write_lock(); ids=han_private.targets(kind,item_id,scope);
  IF kind='booking' THEN
    SELECT * INTO STRICT first_row FROM public.reserveringen WHERE id=item_id;
    IF first_row.user_id<>u AND han_private.role()<>'admin' THEN RAISE EXCEPTION 'Alleen eigen reserveringen wijzigen' USING ERRCODE='42501'; END IF;
  ELSE SELECT * INTO STRICT first_row FROM public.reserveringsverzoeken WHERE id=item_id; END IF;
  PERFORM han_private.validate_item(item,han_private.role()='extern');
  delta=(item->>'date')::date-first_row.date;
  -- Externen mogen alleen binnen dezelfde goedgekeurde ruimte/datum/tijd blijven.
  -- Als één moment uitbreiding vraagt, wordt de volledige gekozen wijziging een verzoek.
  IF kind='booking' THEN
    needs_request=coalesce(convert_to_request,false);
    IF han_private.role()='extern' THEN
      needs_request=needs_request OR EXISTS(
        SELECT 1 FROM public.reserveringen b WHERE b.id=ANY(ids) AND
          (delta<>0 OR b.room_id<>item->>'room_id'
           OR (item->>'start_time')::time<b.start_time
           OR (item->>'end_time')::time>b.end_time));
    END IF;
  END IF;
  -- Een afgesplitste wijziging krijgt een nieuw reeksverband: eerdere items blijven intact.
  IF scope='series' AND cardinality(ids)>1 THEN series_id=gen_random_uuid(); END IF;
  SET CONSTRAINTS public.reserveringen_no_overlap DEFERRED;
  FOR r IN SELECT b.id,b.date FROM public.reserveringen b WHERE kind='booking' AND b.id=ANY(ids)
    UNION ALL SELECT q.id,q.date FROM public.reserveringsverzoeken q WHERE kind='request' AND q.id=ANY(ids)
  LOOP
    next_item=jsonb_set(item,'{date}',to_jsonb((r.date+delta)::text));
    PERFORM han_private.validate_item(next_item,han_private.role()='extern');
    IF kind='booking' AND needs_request THEN
      request_ids=array_append(request_ids,han_private.add_request(next_item,first_row.user_id,series_id));
    ELSIF kind='booking' THEN
      UPDATE public.reserveringen SET name=next_item->>'name',room_id=next_item->>'room_id',date=(next_item->>'date')::date,
        start_time=(next_item->>'start_time')::time,end_time=(next_item->>'end_time')::time,persons=(next_item->>'persons')::int,
        description=next_item->>'description',organization=next_item->>'organization',occasion=next_item->>'occasion',
        motivation=next_item->>'motivation',recurrence_id=series_id WHERE id=r.id;
    ELSE
      UPDATE public.reserveringsverzoeken SET name=next_item->>'name',room_id=next_item->>'room_id',date=(next_item->>'date')::date,
        start_time=(next_item->>'start_time')::time,end_time=(next_item->>'end_time')::time,persons=(next_item->>'persons')::int,
        description=next_item->>'description',organization=next_item->>'organization',occasion=next_item->>'occasion',
        motivation=next_item->>'motivation',recurrence_id=series_id,conflict=han_private.conflicts(next_item) WHERE id=r.id;
    END IF;
    affected=affected+1;
  END LOOP;
  IF kind='booking' AND needs_request THEN
    DELETE FROM public.reserveringen WHERE id=ANY(ids);
    -- De vervallen eigen reserveringen tellen niet mee als conflict van het nieuwe verzoek.
    UPDATE public.reserveringsverzoeken q SET conflict=han_private.conflicts(to_jsonb(q)) WHERE q.id=ANY(request_ids);
  END IF;
  SET CONSTRAINTS public.reserveringen_no_overlap IMMEDIATE;
  IF affected=0 THEN RAISE EXCEPTION 'Niets gewijzigd'; END IF;
  RETURN affected;
END;
$$;

CREATE OR REPLACE FUNCTION public.han_decide_request(item_id uuid,scope text,approve boolean,note text DEFAULT NULL) RETURNS integer
LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE ids uuid[]; r public.reserveringsverzoeken; item jsonb;
BEGIN
  PERFORM han_private.write_lock(); PERFORM han_private.require_admin();
  IF approve IS NULL THEN RAISE EXCEPTION 'Beslissing ontbreekt'; END IF;
  ids=han_private.targets('request',item_id,scope);
  FOR r IN SELECT * FROM public.reserveringsverzoeken WHERE id=ANY(ids) ORDER BY date,start_time,id LOOP
    IF approve THEN
      item=to_jsonb(r)||jsonb_build_object('start_time',to_char(r.start_time,'HH24:MI'),'end_time',to_char(r.end_time,'HH24:MI'));
      PERFORM han_private.validate_item(item);
      PERFORM han_private.add_booking(item,r.user_id,r.recurrence_id);
    END IF;
  END LOOP;
  IF approve THEN
    DELETE FROM public.reserveringsverzoeken WHERE id=ANY(ids);
  ELSE
    UPDATE public.reserveringsverzoeken SET status='rejected',
      handled_by=han_private.uid(),handled_at=now(),admin_note=note WHERE id=ANY(ids);
  END IF;
  RETURN cardinality(ids);
END;
$$;

CREATE OR REPLACE FUNCTION han_private.validate_role_request(target_role text) RETURNS void
LANGUAGE plpgsql SET search_path='' AS $$
DECLARE actor_role text:=han_private.role();
BEGIN
  IF target_role IS NULL OR target_role NOT IN ('intern','admin')
     OR NOT (actor_role='extern' OR (actor_role='intern' AND target_role='admin')) THEN
    RAISE EXCEPTION 'Deze rol kun je niet aanvragen' USING ERRCODE='42501';
  END IF;
END;
$$;

CREATE OR REPLACE FUNCTION public.han_role_request(full_name text,job_title text,motivation text,requested_role text DEFAULT 'intern') RETURNS uuid
LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE u text:=han_private.require_user(); result uuid;
BEGIN
  PERFORM han_private.write_lock(); PERFORM han_private.validate_role_request(requested_role);
  INSERT INTO public.role_requests(user_id,full_name,job_title,motivation,requested_role)
    VALUES(u,full_name,job_title,motivation,requested_role) RETURNING id INTO result;
  RETURN result;
END;
$$;

CREATE OR REPLACE FUNCTION public.han_edit_role_request(item_id uuid,full_name text,job_title text,motivation text,requested_role text) RETURNS integer
LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE u text:=han_private.require_user();
BEGIN
  PERFORM han_private.write_lock(); PERFORM han_private.validate_role_request(requested_role);
  UPDATE public.role_requests r SET full_name=han_edit_role_request.full_name,
    job_title=han_edit_role_request.job_title,motivation=han_edit_role_request.motivation,
    requested_role=han_edit_role_request.requested_role
    WHERE r.id=item_id AND r.user_id=u AND r.status='pending';
  IF NOT FOUND THEN RAISE EXCEPTION 'Open eigen rolverzoek niet gevonden'; END IF;
  RETURN 1;
END;
$$;

CREATE OR REPLACE FUNCTION public.han_cancel_role_request(item_id uuid) RETURNS integer
LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
BEGIN
  PERFORM han_private.write_lock();
  DELETE FROM public.role_requests WHERE id=item_id AND user_id=han_private.require_user() AND status='pending';
  IF NOT FOUND THEN RAISE EXCEPTION 'Open eigen rolverzoek niet gevonden'; END IF;
  RETURN 1;
END;
$$;

CREATE OR REPLACE FUNCTION public.han_decide_role(item_id uuid,approve boolean) RETURNS integer
LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE r public.role_requests;
BEGIN
  PERFORM han_private.write_lock(); PERFORM han_private.require_admin();
  IF approve IS NULL THEN RAISE EXCEPTION 'Beslissing ontbreekt'; END IF;
  SELECT * INTO r FROM public.role_requests WHERE id=item_id AND status='pending';
  IF NOT FOUND THEN RAISE EXCEPTION 'Rolverzoek niet gevonden of al behandeld'; END IF;
  IF r.user_id=han_private.uid() THEN RAISE EXCEPTION 'Je kunt geen eigen rolverzoek behandelen'; END IF;
  IF approve THEN
    UPDATE public.profiles SET role=r.requested_role WHERE id=r.user_id
      AND (role='extern' OR (role='intern' AND r.requested_role='admin'));
    IF NOT FOUND THEN RAISE EXCEPTION 'Profiel ontbreekt of heeft al een andere rol'; END IF;
  END IF;
  UPDATE public.role_requests SET status=CASE WHEN approve THEN 'approved' ELSE 'rejected' END,
    handled_by=han_private.uid(),handled_at=now() WHERE id=item_id;
  RETURN 1;
END;
$$;

CREATE OR REPLACE FUNCTION public.han_occupancy(from_date date,to_date date) RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path='' AS $$
DECLARE result jsonb;
BEGIN
  PERFORM han_private.require_user();
  IF from_date IS NULL OR to_date IS NULL OR to_date<from_date OR to_date-from_date>31 THEN RAISE EXCEPTION 'Kies maximaal 32 dagen'; END IF;
  SELECT coalesce(jsonb_agg(x),'[]'::jsonb) INTO result FROM (
    SELECT CASE WHEN user_id=han_private.uid() OR han_private.role()='admin' THEN id END AS id,
      user_id=han_private.uid() AS mine,room_id,date,start_time,end_time,'confirmed'::text AS status,
      name,organization FROM public.reserveringen WHERE date BETWEEN from_date AND to_date
    UNION ALL SELECT CASE WHEN user_id=han_private.uid() OR han_private.role()='admin' THEN id END,
      user_id=han_private.uid(),room_id,date,start_time,end_time,'pending',
      CASE WHEN user_id=han_private.uid() OR han_private.role()='admin' THEN name END,
      CASE WHEN user_id=han_private.uid() OR han_private.role()='admin' THEN organization END
      FROM public.reserveringsverzoeken WHERE status='pending' AND date BETWEEN from_date AND to_date
  )x;
  IF jsonb_array_length(result)>20000 THEN RAISE EXCEPTION 'Te veel gegevens; kies een kortere periode'; END IF;
  RETURN result;
END;
$$;

-- Geen mutatierechten op tabellen. Alleen geselecteerde RPC's zijn browser-API.
-- Helpers zijn niet rechtstreeks via de standaard public-Data API bereikbaar.
REVOKE ALL ON ALL FUNCTIONS IN SCHEMA han_private FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION han_private.uid(),han_private.role() TO authenticated;
DO $$
DECLARE f record;
BEGIN
  FOR f IN SELECT p.oid::regprocedure AS signature FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
    WHERE n.nspname='public' AND (p.proname LIKE 'han\_%' ESCAPE '\' OR p.proname='import_reserveringen') LOOP
    EXECUTE format('REVOKE ALL ON FUNCTION %s FROM PUBLIC,anon,authenticated',f.signature);
    EXECUTE format('GRANT EXECUTE ON FUNCTION %s TO authenticated',f.signature);
  END LOOP;
END;
$$;
RESET search_path;
END $workflow_migration$;
