-- HAN@Connectr. CLI migration 20260929192403. Apply once after reservation_workflows.
-- Never run reset/basis on live data.
-- One transaction: schema, preserved legacy conversations and API permissions switch together.
BEGIN;

ALTER TABLE public.profiles
  ADD COLUMN first_name text,
  ADD COLUMN last_name text,
  ADD COLUMN name_confirmed_at timestamptz,
  ADD CONSTRAINT profile_names CHECK (
    name_confirmed_at IS NULL OR
    (nullif(btrim(first_name),'') IS NOT NULL AND nullif(btrim(last_name),'') IS NOT NULL
     AND char_length(first_name||' '||last_name)<=120));
ALTER TABLE public.reserveringen ADD COLUMN created_by text REFERENCES public.profiles(id),
  ADD COLUMN name_override boolean NOT NULL DEFAULT false;
ALTER TABLE public.reserveringsverzoeken ADD COLUMN created_by text REFERENCES public.profiles(id);
-- Historical creators are unknown. Do not claim that the owner created a legacy item.
-- A differing legacy name does not prove that a booking was made for a guest.
-- Keep existing names during migration; confirmed profile changes update future items.

CREATE TABLE han_private.notifications (
  id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  recipient_id text NOT NULL REFERENCES public.profiles(id),
  event_id uuid NOT NULL,
  event_type text NOT NULL,
  item_kind text NOT NULL CHECK(item_kind IN ('booking','request','role','case')),
  item_id uuid NOT NULL,
  details jsonb NOT NULL DEFAULT '{}',
  created_at timestamptz NOT NULL DEFAULT now(),
  read_at timestamptz,
  UNIQUE(recipient_id,event_id)
);
CREATE INDEX notifications_recipient ON han_private.notifications(recipient_id,id DESC);
CREATE TABLE han_private.transfers (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  item_kind text NOT NULL, item_id uuid NOT NULL,
  old_owner text NOT NULL, new_owner text NOT NULL,
  performed_by text NOT NULL REFERENCES public.profiles(id),
  performed_at timestamptz NOT NULL DEFAULT now()
);

-- Keep the original rows/columns, but remove every direct browser read path.
ALTER TABLE public.support_messages SET SCHEMA han_private;
DROP POLICY read_support ON han_private.support_messages;
REVOKE ALL ON han_private.support_messages FROM PUBLIC,anon,authenticated;
ALTER TABLE han_private.support_messages
  ADD COLUMN category text NOT NULL DEFAULT 'unclassified' CHECK(category IN ('question','complaint','tip','unclassified')),
  ADD COLUMN anonymous boolean NOT NULL DEFAULT true,
  ADD COLUMN contact_email text CHECK(char_length(contact_email)<=254),
  ADD COLUMN archived_at timestamptz,
  ADD COLUMN version bigint NOT NULL DEFAULT 1,
  ADD CONSTRAINT anonymous_no_contact CHECK(NOT anonymous OR contact_email IS NULL);
CREATE TABLE han_private.case_messages (
  id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  case_id uuid NOT NULL REFERENCES han_private.support_messages(id),
  author_id text REFERENCES public.profiles(id),
  author_role text NOT NULL CHECK(author_role IN ('user','admin')),
  body text NOT NULL CHECK(char_length(btrim(body)) BETWEEN 1 AND 5000),
  created_at timestamptz,
  legacy boolean NOT NULL DEFAULT false
);
CREATE INDEX case_messages_case ON han_private.case_messages(case_id,id);
CREATE TABLE han_private.case_reads (
  case_id uuid NOT NULL REFERENCES han_private.support_messages(id),
  reader_id text NOT NULL REFERENCES public.profiles(id),
  last_message_id bigint NOT NULL DEFAULT 0,
  PRIMARY KEY(case_id,reader_id)
);
INSERT INTO han_private.case_messages(case_id,author_id,author_role,body,created_at,legacy)
 SELECT id,user_id,'user',message,created_at,true FROM han_private.support_messages ORDER BY created_at,id;
INSERT INTO han_private.case_messages(case_id,author_id,author_role,body,created_at,legacy)
 SELECT id,handled_by,'admin',admin_note,handled_at,true FROM han_private.support_messages
 WHERE nullif(btrim(admin_note),'') IS NOT NULL ORDER BY handled_at NULLS LAST,id;

CREATE FUNCTION han_private.require_name(account_id text) RETURNS text
LANGUAGE plpgsql STABLE SET search_path='' AS $$
DECLARE result text;
BEGIN
  SELECT display_name INTO result FROM public.profiles WHERE id=account_id AND name_confirmed_at IS NOT NULL;
  IF result IS NULL THEN RAISE EXCEPTION 'PROFILE_REQUIRED' USING ERRCODE='P0001'; END IF;
  RETURN result;
END;
$$;
CREATE OR REPLACE FUNCTION public.han_ensure_profile(display_name text) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE u text:=han_private.uid(); p public.profiles;
BEGIN
  IF u IS NULL OR u !~ '^user_[A-Za-z0-9]+$' THEN RAISE EXCEPTION 'Geen geldige Clerk-sessie' USING ERRCODE='42501'; END IF;
  -- No email-derived display names for new accounts; old names remain suggestions only.
  INSERT INTO public.profiles(id,role) VALUES(u,'extern') ON CONFLICT(id) DO NOTHING;
  SELECT * INTO STRICT p FROM public.profiles WHERE id=u;
  RETURN to_jsonb(p);
END;
$$;
CREATE FUNCTION public.han_save_profile(first_name text,last_name text) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE u text:=han_private.require_user(); p public.profiles; profile_name text;
BEGIN
  PERFORM han_private.write_lock();
  IF nullif(btrim(first_name),'') IS NULL OR nullif(btrim(last_name),'') IS NULL
     OR char_length(btrim(first_name)||' '||btrim(last_name))>120 THEN RAISE EXCEPTION 'NAME_INVALID'; END IF;
  profile_name=btrim(first_name)||' '||btrim(last_name);
  UPDATE public.profiles p SET first_name=btrim(han_save_profile.first_name),last_name=btrim(han_save_profile.last_name),
    display_name=profile_name,name_confirmed_at=now() WHERE id=u RETURNING * INTO p;
  UPDATE public.reserveringen SET name=profile_name WHERE user_id=u AND NOT name_override
    AND date+end_time>now() AT TIME ZONE 'Europe/Amsterdam';
  UPDATE public.reserveringsverzoeken SET name=profile_name WHERE user_id=u AND status='pending';
  UPDATE public.role_requests SET full_name=profile_name WHERE user_id=u AND status='pending';
  RETURN to_jsonb(p);
END;
$$;
CREATE FUNCTION public.han_find_accounts(search_text text,after_id text DEFAULT '') RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
BEGIN
  PERFORM han_private.require_admin();
  IF char_length(btrim(search_text))<2 THEN RETURN '[]'; END IF;
  RETURN coalesce((SELECT jsonb_agg(to_jsonb(p)) FROM (
    SELECT id,display_name,role,name_confirmed_at IS NOT NULL AS complete FROM public.profiles
    WHERE id>after_id AND (id=btrim(search_text) OR position(lower(btrim(search_text)) in lower(coalesce(display_name,'')))>0)
    ORDER BY id LIMIT 30) p),'[]');
END;
$$;

CREATE FUNCTION han_private.notify(recipient text,event_type text,kind text,item_id uuid,details jsonb DEFAULT '{}',event_id uuid DEFAULT gen_random_uuid())
RETURNS void LANGUAGE plpgsql SET search_path='' AS $$
BEGIN
  IF recipient IS NOT NULL AND recipient IS DISTINCT FROM han_private.uid() THEN
    INSERT INTO han_private.notifications(recipient_id,event_id,event_type,item_kind,item_id,details)
    VALUES(recipient,event_id,event_type,kind,item_id,details) ON CONFLICT ON CONSTRAINT notifications_recipient_id_event_id_key DO NOTHING;
  END IF;
END;
$$;
CREATE FUNCTION han_private.notify_admins(event_type text,kind text,item_id uuid,details jsonb DEFAULT '{}') RETURNS void
LANGUAGE plpgsql SET search_path='' AS $$
DECLARE p record; event_id uuid:=gen_random_uuid();
BEGIN
  FOR p IN SELECT id FROM public.profiles WHERE role='admin' LOOP
    PERFORM han_private.notify(p.id,event_type,kind,item_id,details,event_id);
  END LOOP;
END;
$$;
CREATE FUNCTION han_private.enforce_item_name() RETURNS trigger LANGUAGE plpgsql SET search_path='' AS $$
DECLARE profile_name text;
BEGIN
  PERFORM han_private.require_name(han_private.require_user());
  IF TG_OP='INSERT' THEN
    IF TG_TABLE_NAME<>'role_requests' THEN NEW.created_by=han_private.uid(); END IF;
  END IF;
  SELECT display_name INTO profile_name FROM public.profiles WHERE id=NEW.user_id AND name_confirmed_at IS NOT NULL;
  IF TG_TABLE_NAME='role_requests' THEN
    IF NEW.status='pending' AND profile_name IS NOT NULL THEN NEW.full_name=profile_name; END IF;
  ELSIF TG_TABLE_NAME='reserveringen' THEN
    IF NOT NEW.name_override AND profile_name IS NOT NULL AND
       (TG_OP='INSERT' OR NEW.date+NEW.end_time>now() AT TIME ZONE 'Europe/Amsterdam' OR NEW.user_id IS DISTINCT FROM OLD.user_id)
    THEN NEW.name=profile_name; END IF;
  ELSE
    IF NEW.status='pending' AND profile_name IS NOT NULL THEN NEW.name=profile_name; END IF;
  END IF;
  RETURN NEW;
END;
$$;
CREATE TRIGGER item_name BEFORE INSERT OR UPDATE ON public.reserveringen FOR EACH ROW EXECUTE FUNCTION han_private.enforce_item_name();
CREATE TRIGGER item_name BEFORE INSERT OR UPDATE ON public.reserveringsverzoeken FOR EACH ROW EXECUTE FUNCTION han_private.enforce_item_name();
CREATE TRIGGER item_name BEFORE INSERT OR UPDATE ON public.role_requests FOR EACH ROW EXECUTE FUNCTION han_private.enforce_item_name();

CREATE FUNCTION han_private.item_notifications() RETURNS trigger LANGUAGE plpgsql SET search_path='' AS $$
DECLARE kind text;
BEGIN
  kind=CASE TG_TABLE_NAME WHEN 'reserveringen' THEN 'booking' WHEN 'reserveringsverzoeken' THEN 'request' ELSE 'role' END;
  IF TG_OP='INSERT' AND kind IN ('request','role') THEN
    PERFORM han_private.notify_admins(kind||'_new',kind,NEW.id);
  ELSIF TG_OP='UPDATE' AND kind IN ('request','role') THEN
    IF NEW.status IS DISTINCT FROM OLD.status AND NEW.status IN ('approved','rejected') THEN
      PERFORM han_private.notify(NEW.user_id,kind||'_'||NEW.status,kind,NEW.id);
    END IF;
  ELSIF kind='booking' AND han_private.role()='admin' THEN
    IF TG_OP='DELETE' THEN
      PERFORM han_private.notify(OLD.user_id,'booking_cancelled',kind,OLD.id,jsonb_build_object('date',OLD.date,'room',OLD.room_id));
    ELSIF TG_OP='UPDATE' AND NEW.user_id=OLD.user_id AND
      (to_jsonb(NEW)-ARRAY['name','updated_at','recurrence_id']) IS DISTINCT FROM (to_jsonb(OLD)-ARRAY['name','updated_at','recurrence_id']) THEN
      PERFORM han_private.notify(NEW.user_id,'booking_changed',kind,NEW.id,jsonb_build_object('date',NEW.date,'room',NEW.room_id));
    END IF;
  END IF;
  RETURN NULL;
END;
$$;
CREATE TRIGGER item_notification AFTER INSERT OR UPDATE OR DELETE ON public.reserveringen FOR EACH ROW EXECUTE FUNCTION han_private.item_notifications();
CREATE TRIGGER item_notification AFTER INSERT OR UPDATE ON public.reserveringsverzoeken FOR EACH ROW EXECUTE FUNCTION han_private.item_notifications();
CREATE TRIGGER item_notification AFTER INSERT OR UPDATE ON public.role_requests FOR EACH ROW EXECUTE FUNCTION han_private.item_notifications();

CREATE FUNCTION public.han_admin_book(items jsonb,owner_id text DEFAULT NULL,guest_name text DEFAULT NULL) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE u text:=han_private.require_user(); item jsonb; booking_id uuid; series_id uuid; owner_name text; result jsonb:='[]';
BEGIN
  PERFORM han_private.write_lock(); PERFORM han_private.require_admin(); PERFORM han_private.require_name(u);
  IF (owner_id IS NULL)=(nullif(btrim(guest_name),'') IS NULL) THEN RAISE EXCEPTION 'OWNER_REQUIRED'; END IF;
  IF owner_id IS NOT NULL THEN owner_name=han_private.require_name(owner_id); ELSE owner_id=u;owner_name=btrim(guest_name); END IF;
  IF jsonb_typeof(items) IS DISTINCT FROM 'array' OR jsonb_array_length(items) NOT BETWEEN 1 AND 520 THEN RAISE EXCEPTION 'BATCH_INVALID'; END IF;
  IF jsonb_array_length(items)>1 THEN series_id=gen_random_uuid(); END IF;
  FOR item IN SELECT value FROM jsonb_array_elements(items) LOOP
    item=jsonb_set(item,'{name}',to_jsonb(owner_name));
    PERFORM han_private.validate_item(item);
    INSERT INTO public.reserveringen(user_id,name,room_id,date,start_time,end_time,persons,description,organization,occasion,motivation,recurrence_id,name_override)
    VALUES(owner_id,owner_name,item->>'room_id',(item->>'date')::date,(item->>'start_time')::time,(item->>'end_time')::time,
      (item->>'persons')::int,item->>'description',item->>'organization',item->>'occasion',item->>'motivation',series_id,guest_name IS NOT NULL)
    RETURNING id INTO booking_id;
    PERFORM han_private.notify(owner_id,'booking_by_admin','booking',booking_id,jsonb_build_object('date',item->>'date','room',item->>'room_id'));
    result=result||jsonb_build_array(booking_id);
  END LOOP;
  RETURN jsonb_build_object('confirmed',jsonb_array_length(items),'requested',0,'ids',result);
END;
$$;

-- The same selection generates the preview fingerprint and the committed transfer.
CREATE FUNCTION han_private.transfer_snapshot(kind text,item_id uuid,scope text,new_owner text) RETURNS jsonb
LANGUAGE plpgsql SET search_path='' AS $$
DECLARE ids uuid[]; rows jsonb; old_owner text; target_name text;
BEGIN
  PERFORM han_private.require_admin(); target_name=han_private.require_name(new_owner);
  ids=han_private.targets(kind,item_id,scope);
  IF kind='booking' THEN
    SELECT jsonb_agg(to_jsonb(b) ORDER BY date,start_time,id) INTO rows FROM public.reserveringen b WHERE id=ANY(ids);
  ELSE
    SELECT jsonb_agg(to_jsonb(b) ORDER BY date,start_time,id) INTO rows FROM public.reserveringsverzoeken b WHERE id=ANY(ids);
  END IF;
  old_owner=rows->0->>'user_id';
  RETURN jsonb_build_object('items',rows,'count',cardinality(ids),'old_owner',old_owner,
    'old_name',(SELECT display_name FROM public.profiles WHERE id=old_owner),'new_owner',new_owner,'new_name',target_name,
    'fingerprint',encode(sha256(convert_to(rows::text||new_owner||target_name,'UTF8')),'hex'));
END;
$$;
CREATE FUNCTION public.han_preview_transfer(kind text,item_id uuid,scope text,new_owner text) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
BEGIN
  PERFORM han_private.write_lock();
  RETURN han_private.transfer_snapshot(kind,item_id,scope,new_owner);
END;
$$;
CREATE FUNCTION public.han_transfer(kind text,item_id uuid,scope text,new_owner text,fingerprint text) RETURNS integer
LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE snapshot jsonb; r jsonb; new_series uuid; result int:=0; old_owner text; target_id uuid;
BEGIN
  PERFORM han_private.write_lock(); PERFORM han_private.require_name(han_private.require_user());
  snapshot=han_private.transfer_snapshot(kind,item_id,scope,new_owner);
  IF fingerprint IS DISTINCT FROM snapshot->>'fingerprint' THEN RAISE EXCEPTION 'STALE_ITEM'; END IF;
  old_owner=snapshot->>'old_owner';
  IF old_owner=new_owner THEN RETURN 0; END IF;
  IF (snapshot->>'count')::int>1 THEN new_series=gen_random_uuid(); END IF;
  FOR r IN SELECT value FROM jsonb_array_elements(snapshot->'items') LOOP
    target_id=(r->>'id')::uuid;
    IF kind='booking' THEN
      UPDATE public.reserveringen SET user_id=new_owner,name=snapshot->>'new_name',name_override=false,recurrence_id=new_series WHERE id=target_id;
    ELSE
      UPDATE public.reserveringsverzoeken SET user_id=new_owner,name=snapshot->>'new_name',recurrence_id=new_series WHERE id=target_id;
    END IF;
    INSERT INTO han_private.transfers(item_kind,item_id,old_owner,new_owner,performed_by) VALUES(kind,target_id,old_owner,new_owner,han_private.uid());
    PERFORM han_private.notify(old_owner,'transfer_out',kind,target_id,jsonb_build_object('date',r->>'date','room',r->>'room_id'));
    PERFORM han_private.notify(new_owner,'transfer_in',kind,target_id,jsonb_build_object('date',r->>'date','room',r->>'room_id'));
    result=result+1;
  END LOOP;
  RETURN result;
END;
$$;

-- Detect changes to any selected occurrence, not only the first row in a series.
CREATE FUNCTION han_private.check_item_versions(kind text,ids uuid[],expected_items jsonb) RETURNS void
LANGUAGE plpgsql SET search_path='' AS $$
DECLARE actual jsonb;
BEGIN
  IF jsonb_typeof(expected_items) IS DISTINCT FROM 'array' THEN RAISE EXCEPTION 'STALE_ITEM'; END IF;
  SELECT jsonb_agg(jsonb_build_object('id',r.id,'updated_at',r.updated_at) ORDER BY r.id) INTO actual FROM (
    SELECT id,updated_at FROM public.reserveringen WHERE kind='booking' AND id=ANY(ids)
    UNION ALL SELECT id,updated_at FROM public.reserveringsverzoeken WHERE kind='request' AND id=ANY(ids)) r;
  IF actual IS DISTINCT FROM (SELECT jsonb_agg(jsonb_build_object('id',(e->>'id')::uuid,'updated_at',(e->>'updated_at')::timestamptz) ORDER BY (e->>'id')::uuid) FROM jsonb_array_elements(expected_items) e)
  THEN RAISE EXCEPTION 'STALE_ITEM'; END IF;
END;
$$;
ALTER FUNCTION public.han_edit(text,uuid,text,jsonb,boolean) SET SCHEMA han_private;
ALTER FUNCTION han_private.han_edit(text,uuid,text,jsonb,boolean) RENAME TO edit_before_connectr;
CREATE FUNCTION public.han_edit(kind text,item_id uuid,scope text,item jsonb,expected_items jsonb,convert_to_request boolean DEFAULT false) RETURNS integer
LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE ids uuid[];
BEGIN
  PERFORM han_private.write_lock();
  ids=han_private.targets(kind,item_id,scope);PERFORM han_private.check_item_versions(kind,ids,expected_items);
  RETURN han_private.edit_before_connectr(kind,item_id,scope,item,convert_to_request);
END;
$$;

-- Preserve the existing approval implementation, adding notifications atomically.
ALTER FUNCTION public.han_decide_request(uuid,text,boolean,text) SET SCHEMA han_private;
ALTER FUNCTION han_private.han_decide_request(uuid,text,boolean,text) RENAME TO decide_request_before_connectr;
CREATE FUNCTION public.han_decide_request(item_id uuid,scope text,approve boolean,expected_items jsonb,note text DEFAULT NULL) RETURNS integer
LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE ids uuid[]; originals jsonb; r jsonb; booking_id uuid; count int;
BEGIN
  PERFORM han_private.write_lock(); PERFORM han_private.require_admin();
  ids=han_private.targets('request',item_id,scope);
  PERFORM han_private.check_item_versions('request',ids,expected_items);
  SELECT jsonb_agg(to_jsonb(q)) INTO originals FROM public.reserveringsverzoeken q WHERE id=ANY(ids);
  count=han_private.decide_request_before_connectr(item_id,scope,approve,note);
  IF approve THEN
    FOR r IN SELECT value FROM jsonb_array_elements(originals) LOOP
      SELECT b.id INTO booking_id FROM public.reserveringen b WHERE b.user_id=r->>'user_id' AND b.room_id=r->>'room_id'
        AND b.date=(r->>'date')::date AND b.start_time=(r->>'start_time')::time AND b.end_time=(r->>'end_time')::time;
      PERFORM han_private.notify(r->>'user_id','request_approved','booking',booking_id);
    END LOOP;
  END IF;
  RETURN count;
END;
$$;
CREATE OR REPLACE FUNCTION public.import_reserveringen(import_items jsonb) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE item jsonb; result jsonb:='[]'; booking_id uuid; series_map jsonb:='{}'; series_key text; series_id uuid;
BEGIN
  PERFORM han_private.write_lock(); PERFORM han_private.require_admin();
  IF jsonb_typeof(import_items) IS DISTINCT FROM 'array' OR jsonb_array_length(import_items) NOT BETWEEN 1 AND 520 THEN RAISE EXCEPTION 'Importeer 1 tot 520 regels per bestand'; END IF;
  FOR item IN SELECT value FROM jsonb_array_elements(import_items) LOOP
    PERFORM han_private.validate_item(item); series_key=nullif(item->>'recurrence_id','');series_id=NULL;
    IF series_key IS NOT NULL THEN
      IF NOT series_map ? series_key THEN series_map=jsonb_set(series_map,ARRAY[series_key],to_jsonb(gen_random_uuid()::text)); END IF;
      series_id=(series_map->>series_key)::uuid;
    END IF;
    INSERT INTO public.reserveringen(user_id,name,room_id,date,start_time,end_time,persons,description,organization,occasion,motivation,recurrence_id,name_override)
    VALUES(han_private.uid(),item->>'name',item->>'room_id',(item->>'date')::date,(item->>'start_time')::time,(item->>'end_time')::time,
      (item->>'persons')::int,item->>'description',item->>'organization',item->>'occasion',item->>'motivation',series_id,true) RETURNING id INTO booking_id;
    result=result||jsonb_build_array(jsonb_build_object('row_index',(item->>'import_index')::int,'booking_id',booking_id,'status','imported','message','Geïmporteerd'));
  END LOOP;
  RETURN result;
END;
$$;

CREATE FUNCTION han_private.case_access(item_id uuid) RETURNS han_private.support_messages
LANGUAGE plpgsql STABLE SET search_path='' AS $$
DECLARE c han_private.support_messages; u text:=han_private.require_user();
BEGIN
  SELECT * INTO c FROM han_private.support_messages WHERE id=item_id;
  IF NOT FOUND OR (c.user_id<>u AND han_private.role()<>'admin') THEN RAISE EXCEPTION 'CASE_UNAVAILABLE' USING ERRCODE='42501'; END IF;
  RETURN c;
END;
$$;
CREATE FUNCTION han_private.case_summary(c han_private.support_messages) RETURNS jsonb
LANGUAGE sql STABLE SET search_path='' AS $$
 SELECT jsonb_build_object('id',c.id,'category',c.category,'anonymous',c.anonymous,
   'name',CASE WHEN c.anonymous THEN NULL ELSE (SELECT display_name FROM public.profiles WHERE id=c.user_id) END,
   'contact_email',CASE WHEN NOT c.anonymous AND han_private.role()='admin' THEN c.contact_email ELSE NULL END,
   'message',c.message,'status',c.status,'archived_at',c.archived_at,'version',c.version,'created_at',c.created_at,
   'unread',(SELECT count(*) FROM han_private.case_messages m WHERE m.case_id=c.id AND m.author_id IS DISTINCT FROM han_private.uid()
      AND m.id>coalesce((SELECT last_message_id FROM han_private.case_reads WHERE case_id=c.id AND reader_id=han_private.uid()),0)));
$$;
CREATE FUNCTION public.han_cases(archived boolean DEFAULT false,admin_view boolean DEFAULT false,after_id uuid DEFAULT NULL) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE u text:=han_private.require_user();
BEGIN
  IF admin_view THEN PERFORM han_private.require_admin(); END IF;
  RETURN coalesce((SELECT jsonb_agg(han_private.case_summary(c)) FROM (
    SELECT * FROM han_private.support_messages WHERE (admin_view OR user_id=u) AND (archived_at IS NOT NULL)=archived
      AND (after_id IS NULL OR id>after_id) ORDER BY id LIMIT 100) c),'[]');
END;
$$;
CREATE FUNCTION public.han_case_thread(item_id uuid,after_message bigint DEFAULT 0) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE c han_private.support_messages; messages jsonb;
BEGIN
  c=han_private.case_access(item_id);
  SELECT coalesce(jsonb_agg(to_jsonb(m)),'[]') INTO messages FROM (
    SELECT m.id,m.body,m.created_at,m.legacy,m.author_role,
      CASE WHEN m.author_role='admin' THEN p.display_name WHEN c.anonymous THEN NULL ELSE owner.display_name END AS author_name
    FROM han_private.case_messages m LEFT JOIN public.profiles p ON p.id=m.author_id
    LEFT JOIN public.profiles owner ON owner.id=c.user_id
    WHERE m.case_id=c.id AND m.id>after_message ORDER BY m.id LIMIT 100) m;
  RETURN jsonb_build_object('case',han_private.case_summary(c),'messages',messages);
END;
$$;
CREATE FUNCTION public.han_case_read(item_id uuid,last_message bigint) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE c han_private.support_messages; u text:=han_private.require_user();
BEGIN
  c=han_private.case_access(item_id);
  IF NOT EXISTS(SELECT 1 FROM han_private.case_messages WHERE case_id=item_id AND id=last_message) THEN RAISE EXCEPTION 'MESSAGE_UNAVAILABLE'; END IF;
  INSERT INTO han_private.case_reads(case_id,reader_id,last_message_id) VALUES(item_id,u,last_message)
  ON CONFLICT(case_id,reader_id) DO UPDATE SET last_message_id=greatest(case_reads.last_message_id,excluded.last_message_id);
  UPDATE han_private.notifications SET read_at=coalesce(read_at,now()) WHERE recipient_id=u AND item_kind='case' AND notifications.item_id=han_case_read.item_id
    AND (details->>'message_id')::bigint<=last_message;
  RETURN jsonb_build_object('unread',(SELECT count(*) FROM han_private.case_messages m WHERE m.case_id=item_id
    AND m.author_id IS DISTINCT FROM u AND m.id>(SELECT last_message_id FROM han_private.case_reads WHERE case_id=item_id AND reader_id=u)));
END;
$$;
CREATE FUNCTION public.han_create_case(category text,anonymous boolean,message text,contact_email text DEFAULT NULL) RETURNS uuid
LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE u text:=han_private.require_user(); id uuid; message_id bigint;
BEGIN
  PERFORM han_private.write_lock(); PERFORM han_private.require_name(u);
  IF category IS NULL OR category NOT IN ('question','complaint','tip') OR anonymous IS NULL THEN RAISE EXCEPTION 'CATEGORY_REQUIRED'; END IF;
  IF anonymous THEN contact_email=NULL; END IF;
  IF nullif(btrim(contact_email),'') IS NOT NULL AND contact_email !~ '^[^[:space:]@]+@[^[:space:]@]+\.[^[:space:]@]+$' THEN RAISE EXCEPTION 'EMAIL_INVALID'; END IF;
  INSERT INTO han_private.support_messages(user_id,message,category,anonymous,contact_email)
    VALUES(u,btrim(message),category,anonymous,nullif(btrim(contact_email),'')) RETURNING support_messages.id INTO id;
  INSERT INTO han_private.case_messages(case_id,author_id,author_role,body,created_at) VALUES(id,u,'user',btrim(message),now()) RETURNING case_messages.id INTO message_id;
  PERFORM han_private.notify_admins('case_new','case',id,jsonb_build_object('message_id',message_id));
  RETURN id;
END;
$$;
CREATE FUNCTION public.han_reply_case(item_id uuid,message text,expected_version bigint) RETURNS integer
LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE c han_private.support_messages; u text:=han_private.require_user(); as_admin boolean; message_id bigint;
BEGIN
  PERFORM han_private.write_lock(); c=han_private.case_access(item_id); PERFORM han_private.require_name(u);
  IF c.archived_at IS NOT NULL THEN RAISE EXCEPTION 'CASE_ARCHIVED'; END IF;
  IF c.version IS DISTINCT FROM expected_version THEN RAISE EXCEPTION 'STALE_ITEM'; END IF;
  as_admin=han_private.role()='admin' AND c.user_id<>u;
  INSERT INTO han_private.case_messages(case_id,author_id,author_role,body,created_at)
    VALUES(item_id,u,CASE WHEN as_admin THEN 'admin' ELSE 'user' END,btrim(message),now()) RETURNING id INTO message_id;
  UPDATE han_private.support_messages SET version=version+1,status=CASE WHEN NOT as_admin AND status='afgehandeld' THEN 'open' ELSE status END WHERE id=item_id;
  IF as_admin THEN PERFORM han_private.notify(c.user_id,'case_reply','case',item_id,jsonb_build_object('message_id',message_id));
  ELSE PERFORM han_private.notify_admins('case_user_reply','case',item_id,jsonb_build_object('message_id',message_id)); END IF;
  RETURN 1;
END;
$$;
CREATE FUNCTION public.han_manage_case(item_id uuid,expected_version bigint,new_status text,category text,action text DEFAULT 'save') RETURNS integer
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
  RETURN 1;
END;
$$;
-- Retire the old overwrite API. An old browser must refresh, not overwrite a conversation.
CREATE OR REPLACE FUNCTION public.han_support(message text) RETURNS uuid
LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
BEGIN RAISE EXCEPTION 'APP_REFRESH_REQUIRED'; END;
$$;
CREATE OR REPLACE FUNCTION public.han_handle_support(item_id uuid,new_status text,note text) RETURNS integer
LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
BEGIN RAISE EXCEPTION 'APP_REFRESH_REQUIRED'; END;
$$;

CREATE FUNCTION public.han_notifications(before_id bigint DEFAULT NULL) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE u text:=han_private.require_user(); items jsonb;
BEGIN
  SELECT coalesce(jsonb_agg(to_jsonb(n)),'[]') INTO items FROM (
    SELECT n.id,n.event_type,n.item_kind,n.item_id,n.details,n.created_at,n.read_at,
      CASE n.item_kind WHEN 'booking' THEN EXISTS(SELECT 1 FROM public.reserveringen b WHERE b.id=n.item_id AND (b.user_id=u OR han_private.role()='admin'))
        WHEN 'request' THEN EXISTS(SELECT 1 FROM public.reserveringsverzoeken q WHERE q.id=n.item_id AND (q.user_id=u OR han_private.role()='admin'))
        WHEN 'role' THEN EXISTS(SELECT 1 FROM public.role_requests r WHERE r.id=n.item_id AND (r.user_id=u OR han_private.role()='admin'))
        WHEN 'case' THEN EXISTS(SELECT 1 FROM han_private.support_messages c WHERE c.id=n.item_id AND (c.user_id=u OR han_private.role()='admin')) END AS accessible,
      CASE n.item_kind
        WHEN 'request' THEN (SELECT status FROM public.reserveringsverzoeken WHERE id=n.item_id AND (user_id=u OR han_private.role()='admin'))
        WHEN 'role' THEN (SELECT status FROM public.role_requests WHERE id=n.item_id AND (user_id=u OR han_private.role()='admin'))
        WHEN 'case' THEN (SELECT CASE WHEN archived_at IS NOT NULL THEN 'archived' ELSE status END FROM han_private.support_messages WHERE id=n.item_id AND (user_id=u OR han_private.role()='admin'))
        WHEN 'booking' THEN (SELECT 'confirmed'::text FROM public.reserveringen WHERE id=n.item_id AND (user_id=u OR han_private.role()='admin')) END AS current_status
    FROM han_private.notifications n WHERE recipient_id=u AND (before_id IS NULL OR id<before_id) ORDER BY id DESC LIMIT 50) n;
  RETURN jsonb_build_object('items',items,'unread',(SELECT count(*) FROM han_private.notifications WHERE recipient_id=u AND read_at IS NULL));
END;
$$;
CREATE FUNCTION public.han_read_notification(notification_id bigint) RETURNS integer
LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
BEGIN
  UPDATE han_private.notifications SET read_at=coalesce(read_at,now()) WHERE id=notification_id AND recipient_id=han_private.require_user();
  IF NOT FOUND THEN RAISE EXCEPTION 'NOTIFICATION_UNAVAILABLE' USING ERRCODE='42501'; END IF;
  RETURN 1;
END;
$$;

-- Privacy applies at the API boundary, also when callers request historical dates.
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
      CASE WHEN user_id=u OR admin THEN organization END AS organization
    FROM public.reserveringen WHERE date BETWEEN from_date AND to_date
    UNION ALL
    SELECT CASE WHEN user_id=u OR admin THEN id END,user_id=u,
      room_id,date,start_time,end_time,'pending',
      CASE WHEN user_id=u OR admin THEN name END,
      CASE WHEN user_id=u OR admin THEN organization END
    FROM public.reserveringsverzoeken WHERE status='pending' AND date BETWEEN from_date AND to_date
  ) x;
  IF jsonb_array_length(result)>20000 THEN RAISE EXCEPTION 'Te veel gegevens; kies een kortere periode'; END IF;
  RETURN result;
END;
$$;

-- One row per account/operation; both counters are charged atomically with the write.
-- Failed transactions roll back their charge. This is a successful-write quota,
-- not a substitute for upstream limits on failed requests or distributed traffic.
CREATE TABLE han_private.write_budgets (
  user_id text NOT NULL REFERENCES public.profiles(id),
  operation text NOT NULL,
  hour_start timestamptz NOT NULL,
  hour_units integer NOT NULL CHECK(hour_units>=0),
  day_start timestamptz NOT NULL,
  day_units integer NOT NULL CHECK(day_units>=0),
  PRIMARY KEY(user_id,operation)
);
ALTER TABLE han_private.write_budgets ENABLE ROW LEVEL SECURITY;
CREATE FUNCTION han_private.charge_write(operation text,units integer,hour_limit integer,day_limit integer)
RETURNS void LANGUAGE plpgsql SET search_path='' AS $$
DECLARE u text:=han_private.require_user(); stamp timestamptz:=clock_timestamp(); budget han_private.write_budgets;
BEGIN
  IF operation IS NULL OR units IS NULL OR units<1 OR hour_limit IS NULL OR day_limit IS NULL
     OR units>hour_limit OR hour_limit>day_limit THEN RAISE EXCEPTION 'RATE_LIMITED' USING ERRCODE='PT429'; END IF;
  INSERT INTO han_private.write_budgets AS b(user_id,operation,hour_start,hour_units,day_start,day_units)
    VALUES(u,operation,stamp,units,stamp,units)
  ON CONFLICT ON CONSTRAINT write_budgets_pkey DO UPDATE SET
    hour_start=CASE WHEN b.hour_start<=stamp-interval '1 hour' THEN stamp ELSE b.hour_start END,
    hour_units=CASE WHEN b.hour_start<=stamp-interval '1 hour' THEN units ELSE b.hour_units+units END,
    day_start=CASE WHEN b.day_start<=stamp-interval '1 day' THEN stamp ELSE b.day_start END,
    day_units=CASE WHEN b.day_start<=stamp-interval '1 day' THEN units ELSE b.day_units+units END
  RETURNING * INTO budget;
  IF budget.hour_units>hour_limit OR budget.day_units>day_limit THEN
    RAISE EXCEPTION 'RATE_LIMITED' USING ERRCODE='PT429';
  END IF;
END;
$$;

-- Triggers cover every write path, including series, imports and future RPCs.
CREATE FUNCTION han_private.limit_write() RETURNS trigger LANGUAGE plpgsql SET search_path='' AS $$
BEGIN
  -- Migrations and trusted maintenance without an end-user identity are not user traffic.
  IF han_private.uid() IS NULL THEN RETURN NEW; END IF;
  IF TG_TABLE_NAME='support_messages' AND TG_OP='INSERT' THEN
    PERFORM han_private.charge_write('case_create',1,20,100);
  ELSIF TG_TABLE_NAME='case_messages' THEN
    PERFORM han_private.charge_write('case_message',1,120,600);
  ELSIF TG_TABLE_NAME IN ('reserveringen','reserveringsverzoeken') THEN
    PERFORM han_private.charge_write('booking_write',1,2080,10400);
  ELSIF TG_TABLE_NAME='profiles' THEN
    PERFORM han_private.charge_write('profile_write',1,60,240);
  ELSE
    PERFORM han_private.charge_write('management_write',1,240,1200);
  END IF;
  RETURN NEW;
END;
$$;

-- Successful state changes are recorded without free text, email, passwords or tokens.
CREATE TABLE han_private.audit_events (
  id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  occurred_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  actor_id text,
  resource text NOT NULL,
  resource_id text NOT NULL,
  operation text NOT NULL CHECK(operation IN ('INSERT','UPDATE','DELETE')),
  before_state jsonb NOT NULL,
  after_state jsonb NOT NULL
);
ALTER TABLE han_private.audit_events ENABLE ROW LEVEL SECURITY;
CREATE INDEX audit_events_time_idx ON han_private.audit_events(occurred_at);
CREATE FUNCTION han_private.audit_write() RETURNS trigger LANGUAGE plpgsql SET search_path='' AS $$
DECLARE previous jsonb:=CASE WHEN TG_OP='INSERT' THEN '{}'::jsonb ELSE to_jsonb(OLD) END;
  following jsonb:=CASE WHEN TG_OP='DELETE' THEN '{}'::jsonb ELSE to_jsonb(NEW) END;
  before_state jsonb; after_state jsonb;
BEGIN
  SELECT coalesce(jsonb_object_agg(key,value),'{}'::jsonb) INTO before_state
    FROM jsonb_each(previous) WHERE key IN ('user_id','role','status','active','archived_at','category','anonymous');
  SELECT coalesce(jsonb_object_agg(key,value),'{}'::jsonb) INTO after_state
    FROM jsonb_each(following) WHERE key IN ('user_id','role','status','active','archived_at','category','anonymous');
  INSERT INTO han_private.audit_events(actor_id,resource,resource_id,operation,before_state,after_state)
    VALUES(han_private.uid(),TG_TABLE_SCHEMA||'.'||TG_TABLE_NAME,coalesce(following->>'id',previous->>'id'),TG_OP,before_state,after_state);
  RETURN NULL;
END;
$$;
DO $$
DECLARE target text;
BEGIN
  FOREACH target IN ARRAY ARRAY['public.profiles','public.rooms','public.reserveringen','public.reserveringsverzoeken',
    'public.role_requests','han_private.support_messages','han_private.case_messages'] LOOP
    EXECUTE format('CREATE TRIGGER write_budget BEFORE %s ON %s FOR EACH ROW EXECUTE FUNCTION han_private.limit_write()',
      CASE WHEN target='public.profiles' THEN 'UPDATE' ELSE 'INSERT OR UPDATE' END,target);
    EXECUTE format('CREATE TRIGGER audit_change AFTER INSERT OR UPDATE OR DELETE ON %s FOR EACH ROW EXECUTE FUNCTION han_private.audit_write()',target);
  END LOOP;
END;
$$;

-- JWT signatures/issuer/expiry remain the trusted gateway's responsibility.
-- This additional application check invalidates a signed session immediately on logout.
CREATE TABLE han_private.revoked_sessions (
  session_hash text PRIMARY KEY,
  user_id text NOT NULL,
  revoked_at timestamptz NOT NULL DEFAULT clock_timestamp()
);
CREATE TABLE han_private.blocked_accounts (
  user_id text PRIMARY KEY REFERENCES public.profiles(id),
  blocked_at timestamptz NOT NULL DEFAULT clock_timestamp()
);
CREATE TABLE han_private.trusted_auth (
  issuer text PRIMARY KEY,
  origins text[] NOT NULL CHECK(cardinality(origins)>0)
);
-- Development issuer retained only for the unpublished preparation. Production
-- cutover must replace it together with the Clerk key and gateway integration.
INSERT INTO han_private.trusted_auth VALUES(
  'https://alert-bat-50.clerk.accounts.dev',ARRAY['https://ruimte-reserveren.vercel.app']);
ALTER TABLE han_private.revoked_sessions ENABLE ROW LEVEL SECURITY;
ALTER TABLE han_private.blocked_accounts ENABLE ROW LEVEL SECURITY;
ALTER TABLE han_private.trusted_auth ENABLE ROW LEVEL SECURITY;
CREATE OR REPLACE FUNCTION han_private.uid() RETURNS text
LANGUAGE sql STABLE SECURITY DEFINER SET search_path='' AS $$
  SELECT auth.jwt()->>'sub'
  WHERE auth.jwt()->>'sub' ~ '^user_[A-Za-z0-9]+$'
    AND auth.jwt()->>'sid' ~ '^sess_[A-Za-z0-9]+$'
    AND EXISTS(SELECT 1 FROM han_private.trusted_auth t
      WHERE t.issuer=auth.jwt()->>'iss' AND auth.jwt()->>'azp'=ANY(t.origins))
    AND NOT EXISTS(SELECT 1 FROM han_private.blocked_accounts WHERE user_id=auth.jwt()->>'sub')
    AND NOT EXISTS(SELECT 1 FROM han_private.revoked_sessions
      WHERE session_hash=encode(sha256(convert_to(auth.jwt()->>'sid','UTF8')),'hex'));
$$;
CREATE FUNCTION public.han_end_session() RETURNS integer
LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE u text:=han_private.require_user();
BEGIN
  INSERT INTO han_private.revoked_sessions(session_hash,user_id)
    VALUES(encode(sha256(convert_to(auth.jwt()->>'sid','UTF8')),'hex'),u)
    ON CONFLICT DO NOTHING;
  INSERT INTO han_private.audit_events(actor_id,resource,resource_id,operation,before_state,after_state)
    VALUES(u,'session',u,'UPDATE','{}','{"revoked":true}');
  RETURN 1;
END;
$$;
CREATE FUNCTION public.han_block_account(account_id text) RETURNS integer
LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE u text:=han_private.require_user();
BEGIN
  PERFORM han_private.write_lock(); PERFORM han_private.require_admin();
  IF account_id IS NULL OR account_id=u OR NOT EXISTS(SELECT 1 FROM public.profiles WHERE id=account_id) THEN
    RAISE EXCEPTION 'ACCOUNT_UNAVAILABLE' USING ERRCODE='42501';
  END IF;
  INSERT INTO han_private.blocked_accounts(user_id) VALUES(account_id) ON CONFLICT DO NOTHING;
  INSERT INTO han_private.audit_events(actor_id,resource,resource_id,operation,before_state,after_state)
    VALUES(u,'account_access',account_id,'UPDATE','{}','{"blocked":true}');
  RETURN 1;
END;
$$;

-- Explicit grants; private identities, recipients and message authors are never browser tables.
ALTER TABLE han_private.notifications ENABLE ROW LEVEL SECURITY;
ALTER TABLE han_private.transfers ENABLE ROW LEVEL SECURITY;
ALTER TABLE han_private.case_messages ENABLE ROW LEVEL SECURITY;
ALTER TABLE han_private.case_reads ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON ALL TABLES IN SCHEMA han_private FROM PUBLIC,anon,authenticated;
REVOKE ALL ON ALL SEQUENCES IN SCHEMA han_private FROM PUBLIC,anon,authenticated;
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
COMMIT;
