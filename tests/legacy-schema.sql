-- Testfixture: alleen de live applicatiedefinities, gelezen op 22-09-2026.
-- Geen persoonsgegevens. Alleen gebruiken in een lege lokale testdatabase.
CREATE SCHEMA private;
CREATE SCHEMA extensions;
CREATE EXTENSION btree_gist WITH SCHEMA extensions;
SET search_path=public,extensions;
CREATE TABLE public.profiles (
  id text NOT NULL,
  display_name text,
  role text DEFAULT 'extern'::text NOT NULL,
  created_at timestamp with time zone DEFAULT now() NOT NULL
);
CREATE TABLE public.reserveringen (
  id uuid DEFAULT gen_random_uuid() NOT NULL,
  user_id text DEFAULT (auth.jwt() ->> 'sub'::text) NOT NULL,
  name text NOT NULL,
  room_id text NOT NULL,
  date date NOT NULL,
  start_time time without time zone NOT NULL,
  end_time time without time zone NOT NULL,
  persons integer,
  description text,
  recurrence_id uuid,
  created_at timestamp with time zone DEFAULT now() NOT NULL,
  updated_at timestamp with time zone DEFAULT now() NOT NULL
);
CREATE TABLE public.reserveringsverzoeken (
  id uuid DEFAULT gen_random_uuid() NOT NULL,
  user_id text DEFAULT (auth.jwt() ->> 'sub'::text) NOT NULL,
  name text NOT NULL,
  room_id text NOT NULL,
  date date NOT NULL,
  start_time time without time zone NOT NULL,
  end_time time without time zone NOT NULL,
  persons integer,
  description text,
  organization text,
  occasion text,
  motivation text,
  recurrence_id uuid,
  status text DEFAULT 'pending'::text NOT NULL,
  conflict boolean DEFAULT false NOT NULL,
  handled_by text,
  handled_at timestamp with time zone,
  admin_note text,
  created_at timestamp with time zone DEFAULT now() NOT NULL,
  updated_at timestamp with time zone DEFAULT now() NOT NULL
);
CREATE TABLE public.role_requests (
  id uuid DEFAULT gen_random_uuid() NOT NULL,
  user_id text NOT NULL,
  full_name text NOT NULL,
  job_title text NOT NULL,
  motivation text NOT NULL,
  status text DEFAULT 'pending'::text NOT NULL,
  handled_by text,
  handled_at timestamp with time zone,
  created_at timestamp with time zone DEFAULT now() NOT NULL
);
CREATE TABLE public.rooms (
  id text NOT NULL,
  name text NOT NULL,
  capacity integer,
  notes text,
  active boolean DEFAULT true NOT NULL,
  created_at timestamp with time zone DEFAULT now() NOT NULL
);
CREATE TABLE public.support_messages (
  id uuid DEFAULT gen_random_uuid() NOT NULL,
  user_id text DEFAULT (auth.jwt() ->> 'sub'::text) NOT NULL,
  message text NOT NULL,
  status text DEFAULT 'open'::text NOT NULL,
  admin_note text,
  handled_by text,
  handled_at timestamp with time zone,
  created_at timestamp with time zone DEFAULT now() NOT NULL,
  updated_at timestamp with time zone DEFAULT now() NOT NULL
);
ALTER TABLE public.profiles ADD CONSTRAINT "profiles_pkey" PRIMARY KEY (id);
ALTER TABLE public.profiles ADD CONSTRAINT "profiles_role_check" CHECK ((role = ANY (ARRAY['extern'::text, 'intern'::text, 'admin'::text])));
ALTER TABLE public.rooms ADD CONSTRAINT "rooms_capacity_check" CHECK (((capacity IS NULL) OR (capacity > 0)));
ALTER TABLE public.rooms ADD CONSTRAINT "rooms_pkey" PRIMARY KEY (id);
ALTER TABLE public.reserveringen ADD CONSTRAINT "reserveringen_check" CHECK ((start_time < end_time));
ALTER TABLE public.reserveringen ADD CONSTRAINT "reserveringen_description_check" CHECK (((description IS NULL) OR (char_length(description) <= 500)));
ALTER TABLE public.reserveringen ADD CONSTRAINT "reserveringen_name_check" CHECK (((char_length(name) >= 2) AND (char_length(name) <= 120)));
ALTER TABLE public.reserveringen ADD CONSTRAINT "reserveringen_persons_check" CHECK (((persons IS NULL) OR (persons > 0)));
ALTER TABLE public.reserveringen ADD CONSTRAINT "reserveringen_pkey" PRIMARY KEY (id);
ALTER TABLE public.reserveringen ADD CONSTRAINT "reserveringen_room_id_fkey" FOREIGN KEY (room_id) REFERENCES rooms(id);
ALTER TABLE public.reserveringen ADD CONSTRAINT "reserveringen_room_id_tsrange_excl" EXCLUDE USING gist (room_id WITH =, tsrange((date + start_time), (date + end_time), '[)'::text) WITH &&);
ALTER TABLE public.role_requests ADD CONSTRAINT "role_requests_full_name_check" CHECK (((char_length(full_name) >= 2) AND (char_length(full_name) <= 120)));
ALTER TABLE public.role_requests ADD CONSTRAINT "role_requests_job_title_check" CHECK (((char_length(job_title) >= 2) AND (char_length(job_title) <= 120)));
ALTER TABLE public.role_requests ADD CONSTRAINT "role_requests_motivation_check" CHECK (((char_length(motivation) >= 2) AND (char_length(motivation) <= 500)));
ALTER TABLE public.role_requests ADD CONSTRAINT "role_requests_pkey" PRIMARY KEY (id);
ALTER TABLE public.role_requests ADD CONSTRAINT "role_requests_status_check" CHECK ((status = ANY (ARRAY['pending'::text, 'approved'::text, 'rejected'::text])));
ALTER TABLE public.reserveringsverzoeken ADD CONSTRAINT "reserveringsverzoeken_admin_note_check" CHECK (((admin_note IS NULL) OR (char_length(admin_note) <= 500)));
ALTER TABLE public.reserveringsverzoeken ADD CONSTRAINT "reserveringsverzoeken_check" CHECK ((start_time < end_time));
ALTER TABLE public.reserveringsverzoeken ADD CONSTRAINT "reserveringsverzoeken_description_check" CHECK (((description IS NULL) OR (char_length(description) <= 500)));
ALTER TABLE public.reserveringsverzoeken ADD CONSTRAINT "reserveringsverzoeken_motivation_check" CHECK (((motivation IS NULL) OR (char_length(motivation) <= 500)));
ALTER TABLE public.reserveringsverzoeken ADD CONSTRAINT "reserveringsverzoeken_name_check" CHECK (((char_length(name) >= 2) AND (char_length(name) <= 120)));
ALTER TABLE public.reserveringsverzoeken ADD CONSTRAINT "reserveringsverzoeken_occasion_check" CHECK (((occasion IS NULL) OR (char_length(occasion) <= 120)));
ALTER TABLE public.reserveringsverzoeken ADD CONSTRAINT "reserveringsverzoeken_organization_check" CHECK (((organization IS NULL) OR (char_length(organization) <= 120)));
ALTER TABLE public.reserveringsverzoeken ADD CONSTRAINT "reserveringsverzoeken_persons_check" CHECK (((persons IS NULL) OR (persons > 0)));
ALTER TABLE public.reserveringsverzoeken ADD CONSTRAINT "reserveringsverzoeken_pkey" PRIMARY KEY (id);
ALTER TABLE public.reserveringsverzoeken ADD CONSTRAINT "reserveringsverzoeken_room_id_fkey" FOREIGN KEY (room_id) REFERENCES rooms(id);
ALTER TABLE public.reserveringsverzoeken ADD CONSTRAINT "reserveringsverzoeken_status_check" CHECK ((status = ANY (ARRAY['pending'::text, 'approved'::text, 'rejected'::text])));
ALTER TABLE public.support_messages ADD CONSTRAINT "support_messages_admin_note_check" CHECK (((admin_note IS NULL) OR (char_length(admin_note) <= 500)));
ALTER TABLE public.support_messages ADD CONSTRAINT "support_messages_message_check" CHECK (((char_length(message) >= 5) AND (char_length(message) <= 1500)));
ALTER TABLE public.support_messages ADD CONSTRAINT "support_messages_pkey" PRIMARY KEY (id);
ALTER TABLE public.support_messages ADD CONSTRAINT "support_messages_status_check" CHECK ((status = ANY (ARRAY['open'::text, 'in_behandeling'::text, 'afgehandeld'::text])));
CREATE OR REPLACE FUNCTION public.current_clerk_user_id()
 RETURNS text
 LANGUAGE sql
 STABLE
 SET search_path TO 'public', 'auth', 'pg_temp'
AS $function$
  SELECT auth.jwt()->>'sub';
$function$
;
CREATE OR REPLACE FUNCTION private.is_admin()
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'private', 'extensions', 'auth', 'pg_temp'
AS $function$
  SELECT EXISTS (
    SELECT 1 FROM profiles
    WHERE id = public.current_clerk_user_id() AND role = 'admin'
  );
$function$
;
CREATE OR REPLACE FUNCTION private.is_intern()
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'private', 'extensions', 'auth', 'pg_temp'
AS $function$
  SELECT EXISTS (
    SELECT 1 FROM profiles
    WHERE id = public.current_clerk_user_id() AND role IN ('intern', 'admin')
  );
$function$
;
CREATE OR REPLACE FUNCTION private.assert_admin()
 RETURNS void
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'private', 'extensions', 'auth', 'pg_temp'
AS $function$
BEGIN
  IF NOT public.is_admin() THEN
    RAISE EXCEPTION 'Alleen admins mogen dit doen';
  END IF;
END;
$function$
;
CREATE OR REPLACE FUNCTION public.approve_reserveringsverzoek(verzoek_id uuid, note text DEFAULT NULL::text)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'private', 'extensions', 'auth', 'pg_temp'
AS $function$
DECLARE
  v reserveringsverzoeken%ROWTYPE;
  new_id uuid;
BEGIN
  PERFORM public.assert_admin();

  SELECT * INTO v
  FROM reserveringsverzoeken
  WHERE id = verzoek_id AND status = 'pending';

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Verzoek niet gevonden of al behandeld';
  END IF;

  INSERT INTO reserveringen (
    user_id, name, room_id, date, start_time, end_time,
    persons, description, recurrence_id
  ) VALUES (
    v.user_id, v.name, v.room_id, v.date, v.start_time, v.end_time,
    v.persons, v.description, v.recurrence_id
  )
  RETURNING id INTO new_id;

  UPDATE reserveringsverzoeken
  SET status = 'approved',
      handled_by = public.current_clerk_user_id(),
      handled_at = now(),
      admin_note = note
  WHERE id = verzoek_id;

  RETURN new_id;
END;
$function$
;
CREATE OR REPLACE FUNCTION public.approve_reserveringsverzoek_reeks(verzoek_id uuid, note text DEFAULT NULL::text)
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'private', 'extensions', 'auth', 'pg_temp'
AS $function$
DECLARE
  v_recurrence_id uuid;
  v_count integer := 0;
  v_request record;
BEGIN
  PERFORM public.assert_admin();

  SELECT recurrence_id INTO v_recurrence_id
  FROM reserveringsverzoeken
  WHERE id = verzoek_id AND status = 'pending';

  IF v_recurrence_id IS NULL THEN
    PERFORM public.approve_reserveringsverzoek(verzoek_id, note);
    RETURN 1;
  END IF;

  FOR v_request IN
    SELECT id
    FROM reserveringsverzoeken
    WHERE recurrence_id = v_recurrence_id AND status = 'pending'
    ORDER BY date, start_time
  LOOP
    PERFORM public.approve_reserveringsverzoek(v_request.id, note);
    v_count := v_count + 1;
  END LOOP;

  RETURN v_count;
END;
$function$
;
CREATE OR REPLACE FUNCTION public.approve_role_request(request_id uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'private', 'extensions', 'auth', 'pg_temp'
AS $function$
DECLARE
  v_user_id text;
BEGIN
  PERFORM public.assert_admin();

  SELECT user_id INTO v_user_id
  FROM role_requests
  WHERE id = request_id AND status = 'pending';

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Verzoek niet gevonden of al behandeld';
  END IF;

  UPDATE role_requests
  SET status = 'approved',
      handled_by = public.current_clerk_user_id(),
      handled_at = now()
  WHERE id = request_id;

  UPDATE profiles
  SET role = 'intern'
  WHERE id = v_user_id;
END;
$function$
;
CREATE OR REPLACE FUNCTION public.import_reserveringen(import_items jsonb)
 RETURNS TABLE(row_index integer, booking_id uuid, status text, message text)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'private', 'extensions', 'auth', 'pg_temp'
AS $function$
DECLARE
  v_item record;
  v_booking_id uuid;
  v_recurrence_id uuid;
  v_date date;
  v_start time;
  v_end time;
  v_persons integer;
BEGIN
  PERFORM private.assert_admin();

  IF import_items IS NULL OR jsonb_typeof(import_items) <> 'array' THEN
    RAISE EXCEPTION 'Import moet een JSON-array zijn';
  END IF;

  FOR v_item IN
    SELECT *
    FROM jsonb_to_recordset(import_items) AS x(
      import_index integer,
      name text,
      room_id text,
      date text,
      start_time text,
      end_time text,
      persons integer,
      description text,
      recurrence_id text
    )
  LOOP
    row_index := COALESCE(v_item.import_index, 0);
    booking_id := NULL;

    BEGIN
      v_date := v_item.date::date;
      v_start := v_item.start_time::time;
      v_end := v_item.end_time::time;
      v_persons := v_item.persons;
      v_recurrence_id := NULLIF(v_item.recurrence_id, '')::uuid;

      IF COALESCE(char_length(trim(v_item.name)), 0) NOT BETWEEN 2 AND 120 THEN
        status := 'skipped';
        message := 'Naam ontbreekt of is te lang';
        RETURN NEXT;
        CONTINUE;
      END IF;

      IF v_start >= v_end THEN
        status := 'skipped';
        message := 'Eindtijd moet na begintijd liggen';
        RETURN NEXT;
        CONTINUE;
      END IF;

      IF v_persons IS NOT NULL AND v_persons <= 0 THEN
        status := 'skipped';
        message := 'Aantal personen moet groter zijn dan 0';
        RETURN NEXT;
        CONTINUE;
      END IF;

      IF NOT EXISTS (
        SELECT 1
        FROM public.rooms r
        WHERE r.id = v_item.room_id
          AND r.active = true
      ) THEN
        status := 'skipped';
        message := 'Ruimte niet gevonden of niet actief';
        RETURN NEXT;
        CONTINUE;
      END IF;

      IF EXISTS (
        SELECT 1
        FROM public.reserveringen r
        WHERE r.room_id = v_item.room_id
          AND tsrange(
            (r.date + r.start_time)::timestamp,
            (r.date + r.end_time)::timestamp,
            '[)'
          ) && tsrange(
            (v_date + v_start)::timestamp,
            (v_date + v_end)::timestamp,
            '[)'
          )
      ) THEN
        status := 'skipped';
        message := 'Conflict met bestaande reservering';
        RETURN NEXT;
        CONTINUE;
      END IF;

      INSERT INTO public.reserveringen (
        user_id,
        name,
        room_id,
        date,
        start_time,
        end_time,
        persons,
        description,
        recurrence_id
      ) VALUES (
        public.current_clerk_user_id(),
        trim(v_item.name),
        v_item.room_id,
        v_date,
        v_start,
        v_end,
        v_persons,
        NULLIF(left(COALESCE(v_item.description, ''), 500), ''),
        v_recurrence_id
      )
      RETURNING id INTO v_booking_id;

      booking_id := v_booking_id;
      status := 'imported';
      message := 'Geimporteerd';
      RETURN NEXT;
    EXCEPTION
      WHEN OTHERS THEN
        booking_id := NULL;
        status := 'skipped';
        message := SQLERRM;
        RETURN NEXT;
    END;
  END LOOP;
END;
$function$
;
CREATE OR REPLACE FUNCTION public.public_reserveringen_overzicht()
 RETURNS TABLE(room_id text, date date, start_time time without time zone, end_time time without time zone, status text)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'private', 'extensions', 'auth', 'pg_temp'
AS $function$
  select r.room_id, r.date, r.start_time, r.end_time, 'confirmed'::text as status
  from public.reserveringen r
  where r.user_id <> public.current_clerk_user_id();
$function$
;
CREATE OR REPLACE FUNCTION public.public_reserveringsverzoeken()
 RETURNS TABLE(room_id text, date date, start_time time without time zone, end_time time without time zone, status text)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'private', 'extensions', 'auth', 'pg_temp'
AS $function$
  select rv.room_id, rv.date, rv.start_time, rv.end_time, rv.status
  from public.reserveringsverzoeken rv
  where rv.status = 'pending';
$function$
;
CREATE OR REPLACE FUNCTION public.reject_reserveringsverzoek(verzoek_id uuid, note text DEFAULT NULL::text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'private', 'extensions', 'auth', 'pg_temp'
AS $function$
BEGIN
  PERFORM public.assert_admin();

  UPDATE reserveringsverzoeken
  SET status = 'rejected',
      handled_by = public.current_clerk_user_id(),
      handled_at = now(),
      admin_note = note
  WHERE id = verzoek_id AND status = 'pending';

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Verzoek niet gevonden of al behandeld';
  END IF;
END;
$function$
;
CREATE OR REPLACE FUNCTION public.reject_reserveringsverzoek_reeks(verzoek_id uuid, note text DEFAULT NULL::text)
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'private', 'extensions', 'auth', 'pg_temp'
AS $function$
DECLARE
  v_recurrence_id uuid;
  v_count integer;
BEGIN
  PERFORM public.assert_admin();

  SELECT recurrence_id INTO v_recurrence_id
  FROM reserveringsverzoeken
  WHERE id = verzoek_id AND status = 'pending';

  IF v_recurrence_id IS NULL THEN
    PERFORM public.reject_reserveringsverzoek(verzoek_id, note);
    RETURN 1;
  END IF;

  UPDATE reserveringsverzoeken
  SET status = 'rejected',
      handled_by = public.current_clerk_user_id(),
      handled_at = now(),
      admin_note = note
  WHERE recurrence_id = v_recurrence_id AND status = 'pending';

  GET DIAGNOSTICS v_count = ROW_COUNT;
  RETURN v_count;
END;
$function$
;
CREATE OR REPLACE FUNCTION public.reject_role_request(request_id uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'private', 'extensions', 'auth', 'pg_temp'
AS $function$
BEGIN
  PERFORM public.assert_admin();

  UPDATE role_requests
  SET status = 'rejected',
      handled_by = public.current_clerk_user_id(),
      handled_at = now()
  WHERE id = request_id AND status = 'pending';

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Verzoek niet gevonden of al behandeld';
  END IF;
END;
$function$
;
CREATE OR REPLACE FUNCTION public.set_updated_at()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO 'public'
AS $function$
BEGIN
  NEW.updated_at = now();
  RETURN NEW;
END;
$function$
;
CREATE POLICY "Gebruiker leest eigen profiel" ON public.profiles FOR SELECT TO authenticated USING ((id = current_clerk_user_id()));
CREATE POLICY "Gebruiker maakt eigen profiel" ON public.profiles FOR INSERT TO authenticated WITH CHECK ((id = current_clerk_user_id()));
CREATE POLICY "Admin leest alle profielen" ON public.profiles FOR SELECT TO authenticated USING (private.is_admin());
CREATE POLICY "Admin past profielen aan" ON public.profiles FOR UPDATE TO authenticated USING (private.is_admin()) WITH CHECK (private.is_admin());
CREATE POLICY "Iedereen ziet actieve ruimtes" ON public.rooms FOR SELECT TO authenticated USING (((active = true) OR private.is_admin()));
CREATE POLICY "Admin voegt ruimtes toe" ON public.rooms FOR INSERT TO authenticated WITH CHECK (private.is_admin());
CREATE POLICY "Admin past ruimtes aan" ON public.rooms FOR UPDATE TO authenticated USING (private.is_admin()) WITH CHECK (private.is_admin());
CREATE POLICY "Admin verwijdert ruimtes" ON public.rooms FOR DELETE TO authenticated USING (private.is_admin());
CREATE POLICY "Intern en admin mogen reserveren" ON public.reserveringen FOR INSERT TO authenticated WITH CHECK (((user_id = current_clerk_user_id()) AND private.is_intern()));
CREATE POLICY "Gebruiker annuleert eigen reservering" ON public.reserveringen FOR DELETE TO authenticated USING ((user_id = current_clerk_user_id()));
CREATE POLICY "Admin verwijdert alle reserveringen" ON public.reserveringen FOR DELETE TO authenticated USING (private.is_admin());
CREATE POLICY "Gebruiker ziet eigen rolverzoeken" ON public.role_requests FOR SELECT TO authenticated USING ((user_id = current_clerk_user_id()));
CREATE POLICY "Admin ziet alle rolverzoeken" ON public.role_requests FOR SELECT TO authenticated USING (private.is_admin());
CREATE POLICY "Extern dient rolverzoek in" ON public.role_requests FOR INSERT TO authenticated WITH CHECK (((user_id = current_clerk_user_id()) AND (NOT private.is_intern())));
CREATE POLICY "Gebruiker trekt eigen verzoek in" ON public.role_requests FOR DELETE TO authenticated USING (((user_id = current_clerk_user_id()) AND (status = 'pending'::text)));
CREATE POLICY "Gebruiker ziet eigen reserveringsverzoeken" ON public.reserveringsverzoeken FOR SELECT TO authenticated USING ((user_id = current_clerk_user_id()));
CREATE POLICY "Admin ziet alle reserveringsverzoeken" ON public.reserveringsverzoeken FOR SELECT TO authenticated USING (private.is_admin());
CREATE POLICY "Iedereen dient reserveringsverzoek in" ON public.reserveringsverzoeken FOR INSERT TO authenticated WITH CHECK ((user_id = current_clerk_user_id()));
CREATE POLICY "Gebruiker trekt eigen reserveringsverzoek in" ON public.reserveringsverzoeken FOR DELETE TO authenticated USING (((user_id = current_clerk_user_id()) AND (status = 'pending'::text)));
CREATE POLICY "Admin verwijdert reserveringsverzoeken" ON public.reserveringsverzoeken FOR DELETE TO authenticated USING (private.is_admin());
CREATE POLICY "Gebruiker dient vraag klacht of tip in" ON public.support_messages FOR INSERT TO authenticated WITH CHECK ((user_id = current_clerk_user_id()));
CREATE POLICY "Gebruiker leest eigen vragen klachten en tips" ON public.support_messages FOR SELECT TO authenticated USING ((user_id = current_clerk_user_id()));
CREATE POLICY "Admin leest alle vragen klachten en tips" ON public.support_messages FOR SELECT TO authenticated USING (private.is_admin());
CREATE POLICY "Admin behandelt vragen klachten en tips" ON public.support_messages FOR UPDATE TO authenticated USING (private.is_admin()) WITH CHECK (private.is_admin());
CREATE POLICY "Gebruiker wijzigt eigen reservering" ON public.reserveringen FOR UPDATE TO authenticated USING (((user_id = current_clerk_user_id()) AND private.is_intern())) WITH CHECK (((user_id = current_clerk_user_id()) AND private.is_intern()));
CREATE POLICY "Gebruiker leest eigen reserveringen" ON public.reserveringen FOR SELECT TO authenticated USING (((user_id = current_clerk_user_id()) OR private.is_admin()));
CREATE TRIGGER set_reserveringen_updated_at BEFORE UPDATE ON public.reserveringen FOR EACH ROW EXECUTE FUNCTION set_updated_at();
CREATE TRIGGER set_reserveringsverzoeken_updated_at BEFORE UPDATE ON public.reserveringsverzoeken FOR EACH ROW EXECUTE FUNCTION set_updated_at();
CREATE TRIGGER set_support_messages_updated_at BEFORE UPDATE ON public.support_messages FOR EACH ROW EXECUTE FUNCTION set_updated_at();
RESET search_path;
