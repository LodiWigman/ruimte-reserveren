-- Alleen testfixture: basis van GitHub-release 89cd6e3, NIET live uitvoeren.
-- Clerk-native basis. Alleen op een lege applicatiestructuur, in één transactie.
-- Geen Supabase-systeemschema's of Clerk-accounts wijzigen.
CREATE SCHEMA IF NOT EXISTS extensions;
CREATE EXTENSION IF NOT EXISTS btree_gist WITH SCHEMA extensions;
CREATE SCHEMA han_private;
REVOKE ALL ON SCHEMA han_private FROM PUBLIC, anon;
GRANT USAGE ON SCHEMA public, han_private TO authenticated;
SET search_path = public, extensions;

CREATE TABLE public.profiles (
  id text PRIMARY KEY CHECK (id ~ '^user_[A-Za-z0-9]+$'),
  display_name text CHECK (char_length(display_name) BETWEEN 1 AND 120),
  role text NOT NULL DEFAULT 'extern' CHECK (role IN ('extern','intern','admin')),
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);
CREATE TABLE public.rooms (
  id text PRIMARY KEY CHECK (char_length(btrim(id)) BETWEEN 1 AND 60),
  name text NOT NULL CHECK (char_length(btrim(name)) BETWEEN 1 AND 120),
  capacity integer CHECK (capacity > 0),
  notes text CHECK (char_length(notes) <= 1000),
  active boolean NOT NULL DEFAULT true,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);
CREATE TABLE public.reserveringen (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id text NOT NULL REFERENCES public.profiles(id),
  name text NOT NULL CHECK (char_length(btrim(name)) BETWEEN 2 AND 120),
  room_id text NOT NULL REFERENCES public.rooms(id),
  date date NOT NULL CHECK (date BETWEEN DATE '2000-01-01' AND DATE '2100-12-31'),
  start_time time NOT NULL,
  end_time time NOT NULL,
  persons integer CHECK (persons > 0),
  description text CHECK (char_length(description) <= 500),
  recurrence_id uuid,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  CHECK (start_time < end_time AND end_time < TIME '24:00'),
  CONSTRAINT reserveringen_no_overlap EXCLUDE USING gist (
    room_id WITH =, tsrange(date + start_time, date + end_time, '[)') WITH &&
  ) DEFERRABLE INITIALLY IMMEDIATE
);
CREATE TABLE public.reserveringsverzoeken (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id text NOT NULL REFERENCES public.profiles(id),
  name text NOT NULL CHECK (char_length(btrim(name)) BETWEEN 2 AND 120),
  room_id text NOT NULL REFERENCES public.rooms(id),
  date date NOT NULL CHECK (date BETWEEN DATE '2000-01-01' AND DATE '2100-12-31'),
  start_time time NOT NULL,
  end_time time NOT NULL,
  persons integer CHECK (persons > 0),
  description text CHECK (char_length(description) <= 500),
  organization text CHECK (char_length(organization) <= 120),
  occasion text CHECK (char_length(occasion) <= 120),
  motivation text CHECK (char_length(motivation) <= 500),
  recurrence_id uuid,
  status text NOT NULL DEFAULT 'pending' CHECK (status IN ('pending','approved','rejected')),
  conflict boolean NOT NULL DEFAULT false,
  handled_by text REFERENCES public.profiles(id),
  handled_at timestamptz,
  admin_note text CHECK (char_length(admin_note) <= 500),
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  CHECK (start_time < end_time AND end_time < TIME '24:00'),
  CHECK ((status = 'pending' AND handled_by IS NULL AND handled_at IS NULL)
      OR (status <> 'pending' AND handled_by IS NOT NULL AND handled_at IS NOT NULL))
);
CREATE TABLE public.role_requests (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id text NOT NULL REFERENCES public.profiles(id),
  full_name text NOT NULL CHECK (char_length(btrim(full_name)) BETWEEN 2 AND 120),
  job_title text NOT NULL CHECK (char_length(btrim(job_title)) BETWEEN 2 AND 120),
  motivation text NOT NULL CHECK (char_length(btrim(motivation)) BETWEEN 2 AND 500),
  status text NOT NULL DEFAULT 'pending' CHECK (status IN ('pending','approved','rejected')),
  handled_by text REFERENCES public.profiles(id),
  handled_at timestamptz,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  CHECK ((status = 'pending' AND handled_by IS NULL AND handled_at IS NULL)
      OR (status <> 'pending' AND handled_by IS NOT NULL AND handled_at IS NOT NULL))
);
CREATE TABLE public.support_messages (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id text NOT NULL REFERENCES public.profiles(id),
  message text NOT NULL CHECK (char_length(btrim(message)) BETWEEN 5 AND 1500),
  status text NOT NULL DEFAULT 'open' CHECK (status IN ('open','in_behandeling','afgehandeld')),
  admin_note text CHECK (char_length(admin_note) <= 500),
  handled_by text REFERENCES public.profiles(id),
  handled_at timestamptz,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX reserveringen_user_date ON public.reserveringen(user_id,date,id);
CREATE INDEX reserveringen_date ON public.reserveringen(date,id);
CREATE INDEX reserveringen_series ON public.reserveringen(recurrence_id,date,start_time);
CREATE INDEX verzoeken_user_date ON public.reserveringsverzoeken(user_id,date,id);
CREATE INDEX verzoeken_pending ON public.reserveringsverzoeken(date,id) WHERE status='pending';
CREATE INDEX verzoeken_room ON public.reserveringsverzoeken(room_id);
CREATE INDEX verzoeken_series ON public.reserveringsverzoeken(recurrence_id,date,start_time);
CREATE UNIQUE INDEX one_pending_role ON public.role_requests(user_id) WHERE status='pending';
CREATE INDEX role_requests_user ON public.role_requests(user_id);
CREATE INDEX support_user ON public.support_messages(user_id,created_at);

CREATE FUNCTION han_private.uid() RETURNS text LANGUAGE sql STABLE SET search_path='' AS $$
  SELECT nullif(auth.jwt()->>'sub','');
$$;
CREATE FUNCTION han_private.role() RETURNS text LANGUAGE sql STABLE SECURITY DEFINER SET search_path='' AS $$
  SELECT p.role FROM public.profiles p WHERE p.id=han_private.uid();
$$;
CREATE FUNCTION han_private.require_user() RETURNS text LANGUAGE plpgsql STABLE SET search_path='' AS $$
DECLARE u text := han_private.uid();
BEGIN
  IF u IS NULL OR han_private.role() IS NULL THEN RAISE EXCEPTION 'Log opnieuw in; profiel ontbreekt' USING ERRCODE='42501'; END IF;
  RETURN u;
END;
$$;
CREATE FUNCTION han_private.require_admin() RETURNS void LANGUAGE plpgsql STABLE SET search_path='' AS $$
BEGIN
  IF han_private.role() IS DISTINCT FROM 'admin' THEN RAISE EXCEPTION 'Alleen admins mogen dit doen' USING ERRCODE='42501'; END IF;
END;
$$;
CREATE FUNCTION han_private.touch() RETURNS trigger LANGUAGE plpgsql SET search_path='' AS $$
BEGIN NEW.updated_at=clock_timestamp(); RETURN NEW; END;
$$;

DO $$
DECLARE t text;
BEGIN
  FOREACH t IN ARRAY ARRAY['profiles','rooms','reserveringen','reserveringsverzoeken','role_requests','support_messages'] LOOP
    EXECUTE format('ALTER TABLE public.%I ENABLE ROW LEVEL SECURITY',t);
    EXECUTE format('REVOKE ALL ON public.%I FROM PUBLIC, anon, authenticated',t);
    EXECUTE format('GRANT SELECT ON public.%I TO authenticated',t);
    EXECUTE format('CREATE TRIGGER updated_at BEFORE UPDATE ON public.%I FOR EACH ROW EXECUTE FUNCTION han_private.touch()',t);
  END LOOP;
END;
$$;
CREATE POLICY read_profiles ON public.profiles FOR SELECT TO authenticated
  USING(id=(SELECT han_private.uid()) OR (SELECT han_private.role())='admin');
CREATE POLICY read_rooms ON public.rooms FOR SELECT TO authenticated
  USING(active OR (SELECT han_private.role())='admin');
CREATE POLICY read_bookings ON public.reserveringen FOR SELECT TO authenticated
  USING(user_id=(SELECT han_private.uid()) OR (SELECT han_private.role())='admin');
CREATE POLICY read_requests ON public.reserveringsverzoeken FOR SELECT TO authenticated
  USING(user_id=(SELECT han_private.uid()) OR (SELECT han_private.role())='admin');
CREATE POLICY read_roles ON public.role_requests FOR SELECT TO authenticated
  USING(user_id=(SELECT han_private.uid()) OR (SELECT han_private.role())='admin');
CREATE POLICY read_support ON public.support_messages FOR SELECT TO authenticated
  USING(user_id=(SELECT han_private.uid()) OR (SELECT han_private.role())='admin');

CREATE FUNCTION public.han_ensure_profile(display_name text) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE u text:=han_private.uid(); p public.profiles;
BEGIN
  IF u IS NULL OR u !~ '^user_[A-Za-z0-9]+$' THEN RAISE EXCEPTION 'Geen geldige Clerk-sessie' USING ERRCODE='42501'; END IF;
  INSERT INTO public.profiles(id,display_name,role) VALUES(u,btrim(display_name),'extern') ON CONFLICT(id) DO NOTHING;
  SELECT * INTO STRICT p FROM public.profiles WHERE id=u;
  RETURN to_jsonb(p);
END;
$$;

-- Alle app-mutaties nemen dezelfde korte transactielock. Dit maakt conflictdetectie
-- en reeksselectie consistent bij gelijktijdige gebruikers. De GiST-constraint
-- blijft de laatste bescherming, ook tegen beheer-SQL buiten deze functies.
CREATE FUNCTION han_private.write_lock() RETURNS void LANGUAGE sql SET search_path='' AS $$
  SELECT pg_advisory_xact_lock(782461903);
$$;
CREATE FUNCTION han_private.validate_item(item jsonb, external_request boolean DEFAULT false)
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
  IF external_request AND (nullif(btrim(item->>'organization'),'') IS NULL OR nullif(btrim(item->>'occasion'),'') IS NULL OR nullif(btrim(item->>'motivation'),'') IS NULL) THEN
    RAISE EXCEPTION 'Organisatie, gelegenheid en motivatie zijn verplicht voor externen';
  END IF;
END;
$$;
CREATE FUNCTION han_private.conflicts(item jsonb, excluded uuid[] DEFAULT '{}') RETURNS boolean
LANGUAGE sql STABLE SET search_path='' AS $$
  SELECT EXISTS(SELECT 1 FROM public.reserveringen b WHERE b.room_id=item->>'room_id'
    AND b.date=(item->>'date')::date AND b.start_time<(item->>'end_time')::time
    AND b.end_time>(item->>'start_time')::time AND NOT(b.id=ANY(excluded)));
$$;
CREATE FUNCTION han_private.add_booking(item jsonb, owner_id text, series_id uuid) RETURNS uuid
LANGUAGE plpgsql SET search_path='' AS $$
DECLARE result uuid;
BEGIN
  INSERT INTO public.reserveringen(user_id,name,room_id,date,start_time,end_time,persons,description,recurrence_id)
  VALUES(owner_id,item->>'name',item->>'room_id',(item->>'date')::date,(item->>'start_time')::time,(item->>'end_time')::time,
    (item->>'persons')::integer,item->>'description',series_id) RETURNING id INTO result;
  RETURN result;
END;
$$;
CREATE FUNCTION han_private.add_request(item jsonb, owner_id text, series_id uuid) RETURNS uuid
LANGUAGE plpgsql SET search_path='' AS $$
DECLARE result uuid;
BEGIN
  INSERT INTO public.reserveringsverzoeken(user_id,name,room_id,date,start_time,end_time,persons,description,recurrence_id,organization,occasion,motivation,conflict)
  VALUES(owner_id,item->>'name',item->>'room_id',(item->>'date')::date,(item->>'start_time')::time,(item->>'end_time')::time,
    (item->>'persons')::integer,item->>'description',series_id,item->>'organization',item->>'occasion',item->>'motivation',han_private.conflicts(item)) RETURNING id INTO result;
  RETURN result;
END;
$$;
CREATE FUNCTION public.han_create_bookings(items jsonb) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE u text:=han_private.require_user(); item jsonb; series_id uuid; direct_count int:=0; request_count int:=0;
BEGIN
  PERFORM han_private.write_lock();
  IF jsonb_typeof(items) IS DISTINCT FROM 'array' OR jsonb_array_length(items) NOT BETWEEN 1 AND 520 THEN RAISE EXCEPTION 'Gebruik 1 tot 520 gebeurtenissen'; END IF;
  IF jsonb_array_length(items)>1 THEN series_id=gen_random_uuid(); END IF;
  FOR item IN SELECT value FROM jsonb_array_elements(items) LOOP
    PERFORM han_private.validate_item(item,han_private.role()='extern');
    IF han_private.role()='extern' OR han_private.conflicts(item) THEN
      PERFORM han_private.add_request(item,u,series_id); request_count=request_count+1;
    ELSE
      PERFORM han_private.add_booking(item,u,series_id); direct_count=direct_count+1;
    END IF;
  END LOOP;
  RETURN jsonb_build_object('confirmed',direct_count,'requested',request_count);
END;
$$;

-- Server selects the entire affected series; the browser never supplies trusted IDs/owners.
CREATE FUNCTION han_private.targets(kind text, item_id uuid, scope text) RETURNS uuid[]
LANGUAGE plpgsql SET search_path='' AS $$
DECLARE first_row record; ids uuid[]; u text:=han_private.require_user();
BEGIN
  IF kind IS NULL OR kind NOT IN ('booking','request') OR scope IS NULL OR scope NOT IN ('single','series') THEN RAISE EXCEPTION 'Ongeldige actie'; END IF;
  IF kind='booking' THEN
    SELECT * INTO first_row FROM public.reserveringen WHERE id=item_id;
  ELSE
    SELECT * INTO first_row FROM public.reserveringsverzoeken WHERE id=item_id AND status='pending';
  END IF;
  IF NOT FOUND THEN RAISE EXCEPTION 'Item niet gevonden of al behandeld'; END IF;
  IF first_row.user_id<>u AND han_private.role()<>'admin' THEN RAISE EXCEPTION 'Geen toegang tot dit item' USING ERRCODE='42501'; END IF;
  IF scope='single' OR first_row.recurrence_id IS NULL THEN RETURN ARRAY[item_id]; END IF;
  IF kind='booking' THEN
    SELECT array_agg(id ORDER BY date,start_time,id) INTO ids FROM public.reserveringen
      WHERE recurrence_id=first_row.recurrence_id AND user_id=first_row.user_id AND (date,start_time)>=(first_row.date,first_row.start_time);
  ELSE
    SELECT array_agg(id ORDER BY date,start_time,id) INTO ids FROM public.reserveringsverzoeken
      WHERE recurrence_id=first_row.recurrence_id AND user_id=first_row.user_id AND status='pending' AND (date,start_time)>=(first_row.date,first_row.start_time);
  END IF;
  RETURN ids;
END;
$$;
CREATE FUNCTION public.han_cancel(kind text,item_id uuid,scope text DEFAULT 'single') RETURNS integer
LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE ids uuid[]; affected int;
BEGIN
  PERFORM han_private.write_lock(); ids=han_private.targets(kind,item_id,scope);
  IF kind='booking' THEN DELETE FROM public.reserveringen WHERE id=ANY(ids);
  ELSE DELETE FROM public.reserveringsverzoeken WHERE id=ANY(ids); END IF;
  GET DIAGNOSTICS affected=ROW_COUNT;
  IF affected=0 THEN RAISE EXCEPTION 'Niets gewijzigd; ververs het overzicht'; END IF;
  RETURN affected;
END;
$$;
CREATE FUNCTION public.han_edit(kind text,item_id uuid,scope text,item jsonb,convert_to_request boolean DEFAULT false) RETURNS integer
LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE ids uuid[]; first_row record; r record; next_item jsonb; delta int; series_id uuid; affected int:=0; u text:=han_private.require_user();
BEGIN
  PERFORM han_private.write_lock(); ids=han_private.targets(kind,item_id,scope);
  IF kind='booking' THEN
    SELECT * INTO STRICT first_row FROM public.reserveringen WHERE id=item_id;
    IF first_row.user_id<>u OR han_private.role() NOT IN ('intern','admin') THEN RAISE EXCEPTION 'Alleen eigen reserveringen wijzigen als intern/admin' USING ERRCODE='42501'; END IF;
  ELSE SELECT * INTO STRICT first_row FROM public.reserveringsverzoeken WHERE id=item_id; END IF;
  PERFORM han_private.validate_item(item,kind='request' AND han_private.role()='extern');
  delta=(item->>'date')::date-first_row.date;
  -- Een afgesplitste wijziging krijgt een nieuw reeksverband: eerdere items blijven intact.
  IF scope='series' AND cardinality(ids)>1 THEN series_id=gen_random_uuid(); END IF;
  SET CONSTRAINTS public.reserveringen_no_overlap DEFERRED;
  FOR r IN SELECT b.id,b.date FROM public.reserveringen b WHERE kind='booking' AND b.id=ANY(ids)
    UNION ALL SELECT q.id,q.date FROM public.reserveringsverzoeken q WHERE kind='request' AND q.id=ANY(ids)
  LOOP
    next_item=jsonb_set(item,'{date}',to_jsonb((r.date+delta)::text));
    PERFORM han_private.validate_item(next_item,kind='request' AND han_private.role()='extern');
    IF kind='booking' AND convert_to_request IS TRUE THEN
      PERFORM han_private.add_request(next_item,first_row.user_id,series_id);
    ELSIF kind='booking' THEN
      UPDATE public.reserveringen SET name=next_item->>'name',room_id=next_item->>'room_id',date=(next_item->>'date')::date,
        start_time=(next_item->>'start_time')::time,end_time=(next_item->>'end_time')::time,persons=(next_item->>'persons')::int,
        description=next_item->>'description',recurrence_id=series_id WHERE id=r.id;
    ELSE
      UPDATE public.reserveringsverzoeken SET name=next_item->>'name',room_id=next_item->>'room_id',date=(next_item->>'date')::date,
        start_time=(next_item->>'start_time')::time,end_time=(next_item->>'end_time')::time,persons=(next_item->>'persons')::int,
        description=next_item->>'description',organization=next_item->>'organization',occasion=next_item->>'occasion',
        motivation=next_item->>'motivation',recurrence_id=series_id,conflict=han_private.conflicts(next_item) WHERE id=r.id;
    END IF;
    affected=affected+1;
  END LOOP;
  IF kind='booking' AND convert_to_request IS TRUE THEN DELETE FROM public.reserveringen WHERE id=ANY(ids); END IF;
  SET CONSTRAINTS public.reserveringen_no_overlap IMMEDIATE;
  IF affected=0 THEN RAISE EXCEPTION 'Niets gewijzigd'; END IF;
  RETURN affected;
END;
$$;
CREATE FUNCTION public.han_decide_request(item_id uuid,scope text,approve boolean,note text DEFAULT NULL) RETURNS integer
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
  UPDATE public.reserveringsverzoeken SET status=CASE WHEN approve THEN 'approved' ELSE 'rejected' END,
    handled_by=han_private.uid(),handled_at=now(),admin_note=note WHERE id=ANY(ids);
  RETURN cardinality(ids);
END;
$$;
CREATE FUNCTION public.han_role_request(full_name text,job_title text,motivation text) RETURNS uuid
LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE u text:=han_private.require_user(); result uuid;
BEGIN
  PERFORM han_private.write_lock();
  IF han_private.role()<>'extern' THEN RAISE EXCEPTION 'Alleen externen vragen een interne rol aan'; END IF;
  INSERT INTO public.role_requests(user_id,full_name,job_title,motivation) VALUES(u,full_name,job_title,motivation) RETURNING id INTO result;
  RETURN result;
END;
$$;
CREATE FUNCTION public.han_decide_role(item_id uuid,approve boolean) RETURNS integer
LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE r public.role_requests;
BEGIN
  PERFORM han_private.write_lock(); PERFORM han_private.require_admin();
  IF approve IS NULL THEN RAISE EXCEPTION 'Beslissing ontbreekt'; END IF;
  SELECT * INTO r FROM public.role_requests WHERE id=item_id AND status='pending';
  IF NOT FOUND THEN RAISE EXCEPTION 'Rolverzoek niet gevonden of al behandeld'; END IF;
  IF approve THEN
    UPDATE public.profiles SET role='intern' WHERE id=r.user_id AND role='extern';
    IF NOT FOUND THEN RAISE EXCEPTION 'Profiel ontbreekt of heeft al een andere rol'; END IF;
  END IF;
  UPDATE public.role_requests SET status=CASE WHEN approve THEN 'approved' ELSE 'rejected' END,
    handled_by=han_private.uid(),handled_at=now() WHERE id=item_id;
  RETURN 1;
END;
$$;
CREATE FUNCTION public.han_support(message text) RETURNS uuid
LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE u text:=han_private.require_user(); result uuid;
BEGIN
  INSERT INTO public.support_messages(user_id,message) VALUES(u,message) RETURNING id INTO result;
  RETURN result;
END;
$$;
CREATE FUNCTION public.han_handle_support(item_id uuid,new_status text,note text) RETURNS integer
LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
BEGIN
  PERFORM han_private.require_admin();
  UPDATE public.support_messages SET status=new_status,admin_note=note,handled_by=han_private.uid(),handled_at=now() WHERE id=item_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'Bericht niet gevonden'; END IF;
  RETURN 1;
END;
$$;
CREATE FUNCTION public.han_save_rooms(items jsonb) RETURNS integer
LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE item jsonb; result int:=0;
BEGIN
  PERFORM han_private.write_lock(); PERFORM han_private.require_admin();
  IF jsonb_typeof(items) IS DISTINCT FROM 'array' OR jsonb_array_length(items) NOT BETWEEN 1 AND 200 THEN RAISE EXCEPTION 'Ongeldige ruimtelijst'; END IF;
  FOR item IN SELECT value FROM jsonb_array_elements(items) LOOP
    IF coalesce(item->>'original_id','')<>'' THEN
      UPDATE public.rooms SET name=item->>'name',capacity=(item->>'capacity')::int,notes=item->>'notes',active=(item->>'active')::boolean WHERE id=item->>'original_id';
      IF NOT FOUND THEN RAISE EXCEPTION 'Ruimte niet gevonden'; END IF;
    ELSE
      INSERT INTO public.rooms(id,name,capacity,notes,active) VALUES(item->>'id',item->>'name',(item->>'capacity')::int,item->>'notes',(item->>'active')::boolean);
    END IF;
    result=result+1;
  END LOOP;
  RETURN result;
END;
$$;
CREATE FUNCTION public.han_occupancy(from_date date,to_date date) RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path='' AS $$
DECLARE result jsonb;
BEGIN
  PERFORM han_private.require_user();
  IF from_date IS NULL OR to_date IS NULL OR to_date<from_date OR to_date-from_date>31 THEN RAISE EXCEPTION 'Kies maximaal 32 dagen'; END IF;
  SELECT coalesce(jsonb_agg(x),'[]'::jsonb) INTO result FROM (
    SELECT room_id,date,start_time,end_time,'confirmed'::text AS status FROM public.reserveringen WHERE date BETWEEN from_date AND to_date
    UNION ALL SELECT room_id,date,start_time,end_time,'pending' FROM public.reserveringsverzoeken WHERE status='pending' AND date BETWEEN from_date AND to_date
  )x;
  IF jsonb_array_length(result)>20000 THEN RAISE EXCEPTION 'Te veel gegevens; kies een kortere periode'; END IF;
  RETURN result;
END;
$$;
CREATE FUNCTION public.han_availability(items jsonb,exclude_id uuid DEFAULT NULL,scope text DEFAULT 'single') RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path='' AS $$
DECLARE item jsonb; ids uuid[]:='{}'; result jsonb:='[]';
BEGIN
  PERFORM han_private.require_user();
  IF jsonb_typeof(items) IS DISTINCT FROM 'array' OR jsonb_array_length(items) NOT BETWEEN 1 AND 520 THEN RAISE EXCEPTION 'Ongeldige periode'; END IF;
  IF exclude_id IS NOT NULL THEN ids=han_private.targets('booking',exclude_id,scope); END IF;
  FOR item IN SELECT value FROM jsonb_array_elements(items) LOOP
    PERFORM han_private.validate_item(item);
    result=result||jsonb_build_array(jsonb_build_object('date',item->>'date','conflict',han_private.conflicts(item,ids)));
  END LOOP;
  RETURN result;
END;
$$;
CREATE FUNCTION public.import_reserveringen(import_items jsonb) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE item jsonb; result jsonb:='[]'; booking_id uuid; series_map jsonb:='{}'; series_key text; series_id uuid;
BEGIN
  PERFORM han_private.write_lock(); PERFORM han_private.require_admin();
  IF jsonb_typeof(import_items) IS DISTINCT FROM 'array' OR jsonb_array_length(import_items) NOT BETWEEN 1 AND 520 THEN RAISE EXCEPTION 'Importeer 1 tot 520 regels per bestand'; END IF;
  FOR item IN SELECT value FROM jsonb_array_elements(import_items) LOOP
    PERFORM han_private.validate_item(item);
    series_key=nullif(item->>'recurrence_id',''); series_id=NULL;
    IF series_key IS NOT NULL THEN
      IF NOT series_map ? series_key THEN series_map=jsonb_set(series_map,ARRAY[series_key],to_jsonb(gen_random_uuid()::text)); END IF;
      series_id=(series_map->>series_key)::uuid;
    END IF;
    booking_id=han_private.add_booking(item,han_private.uid(),series_id);
    result=result||jsonb_build_array(jsonb_build_object('row_index',(item->>'import_index')::int,'booking_id',booking_id,'status','imported','message','Geïmporteerd'));
  END LOOP;
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
