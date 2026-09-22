-- ============================================================
-- WebReserv | 08_clerk_auth_migration.sql
-- Zet de database om van Supabase Auth UUID's naar Clerk user ids.
--
-- Vooraf:
-- 1. Activeer in Clerk de Supabase integration.
-- 2. Voeg in Supabase Authentication > Sign In / Providers de Clerk provider toe.
-- 3. Vul in github_index.html je CLERK_PUBLISHABLE_KEY in.
--
-- Let op:
-- - Bestaande user_id waarden worden naar text omgezet, maar oude Supabase
--   Auth-gebruikers matchen niet automatisch met nieuwe Clerk-gebruikers.
-- - Maak handmatig je eerste admin door in profiles.role = 'admin' te zetten.
-- ============================================================

ALTER TABLE profiles              DISABLE ROW LEVEL SECURITY;
ALTER TABLE rooms                 DISABLE ROW LEVEL SECURITY;
ALTER TABLE reserveringen         DISABLE ROW LEVEL SECURITY;
ALTER TABLE role_requests         DISABLE ROW LEVEL SECURITY;
ALTER TABLE reserveringsverzoeken DISABLE ROW LEVEL SECURITY;
ALTER TABLE support_messages      DISABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Gebruiker leest eigen profiel" ON profiles;
DROP POLICY IF EXISTS "Admin leest alle profielen" ON profiles;
DROP POLICY IF EXISTS "Admin past profielen aan" ON profiles;
DROP POLICY IF EXISTS "Gebruiker maakt eigen profiel" ON profiles;

DROP POLICY IF EXISTS "Iedereen ziet actieve ruimtes" ON rooms;
DROP POLICY IF EXISTS "Admin voegt ruimtes toe" ON rooms;
DROP POLICY IF EXISTS "Admin past ruimtes aan" ON rooms;
DROP POLICY IF EXISTS "Admin verwijdert ruimtes" ON rooms;

DROP POLICY IF EXISTS "Iedereen ziet reserveringen" ON reserveringen;
DROP POLICY IF EXISTS "Intern en admin mogen reserveren" ON reserveringen;
DROP POLICY IF EXISTS "Gebruiker annuleert eigen reservering" ON reserveringen;
DROP POLICY IF EXISTS "Admin verwijdert alle reserveringen" ON reserveringen;

DROP POLICY IF EXISTS "Gebruiker ziet eigen rolverzoeken" ON role_requests;
DROP POLICY IF EXISTS "Admin ziet alle rolverzoeken" ON role_requests;
DROP POLICY IF EXISTS "Extern dient rolverzoek in" ON role_requests;
DROP POLICY IF EXISTS "Gebruiker trekt eigen verzoek in" ON role_requests;

DROP POLICY IF EXISTS "Gebruiker ziet eigen reserveringsverzoeken" ON reserveringsverzoeken;
DROP POLICY IF EXISTS "Admin ziet alle reserveringsverzoeken" ON reserveringsverzoeken;
DROP POLICY IF EXISTS "Iedereen dient reserveringsverzoek in" ON reserveringsverzoeken;
DROP POLICY IF EXISTS "Gebruiker trekt eigen reserveringsverzoek in" ON reserveringsverzoeken;
DROP POLICY IF EXISTS "Admin verwijdert reserveringsverzoeken" ON reserveringsverzoeken;

DROP POLICY IF EXISTS "Gebruiker dient vraag klacht of tip in" ON support_messages;
DROP POLICY IF EXISTS "Gebruiker leest eigen vragen klachten en tips" ON support_messages;
DROP POLICY IF EXISTS "Admin leest alle vragen klachten en tips" ON support_messages;
DROP POLICY IF EXISTS "Admin behandelt vragen klachten en tips" ON support_messages;

DO $$
DECLARE
  p record;
BEGIN
  FOR p IN
    SELECT schemaname, tablename, policyname
    FROM pg_policies
    WHERE schemaname = 'public'
      AND tablename IN (
        'profiles',
        'rooms',
        'reserveringen',
        'role_requests',
        'reserveringsverzoeken',
        'support_messages'
      )
  LOOP
    EXECUTE format('DROP POLICY IF EXISTS %I ON %I.%I', p.policyname, p.schemaname, p.tablename);
  END LOOP;
END $$;

DROP TRIGGER IF EXISTS on_auth_user_created ON auth.users;
DROP FUNCTION IF EXISTS public.handle_new_user();

DO $$
DECLARE
  r record;
BEGIN
  FOR r IN
    SELECT conrelid::regclass AS table_name, conname
    FROM pg_constraint
    WHERE contype = 'f'
      AND connamespace = 'public'::regnamespace
      AND confrelid = 'auth.users'::regclass
  LOOP
    EXECUTE format('ALTER TABLE %s DROP CONSTRAINT %I', r.table_name, r.conname);
  END LOOP;
END $$;

ALTER TABLE profiles
  ALTER COLUMN id TYPE text USING id::text;

ALTER TABLE reserveringen
  ALTER COLUMN user_id DROP DEFAULT,
  ALTER COLUMN user_id TYPE text USING user_id::text,
  ALTER COLUMN user_id SET DEFAULT (auth.jwt()->>'sub');

ALTER TABLE role_requests
  ALTER COLUMN user_id TYPE text USING user_id::text,
  ALTER COLUMN handled_by TYPE text USING handled_by::text;

ALTER TABLE reserveringsverzoeken
  ALTER COLUMN user_id DROP DEFAULT,
  ALTER COLUMN user_id TYPE text USING user_id::text,
  ALTER COLUMN user_id SET DEFAULT (auth.jwt()->>'sub'),
  ALTER COLUMN handled_by TYPE text USING handled_by::text;

ALTER TABLE support_messages
  ALTER COLUMN user_id DROP DEFAULT,
  ALTER COLUMN user_id TYPE text USING user_id::text,
  ALTER COLUMN user_id SET DEFAULT (auth.jwt()->>'sub'),
  ALTER COLUMN handled_by TYPE text USING handled_by::text;

CREATE OR REPLACE FUNCTION public.current_clerk_user_id()
RETURNS text
LANGUAGE sql
STABLE
SET search_path = public, auth, pg_temp
AS $$
  SELECT auth.jwt()->>'sub';
$$;

CREATE SCHEMA IF NOT EXISTS private;

CREATE OR REPLACE FUNCTION private.is_admin()
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public, private, extensions, auth, pg_temp
AS $$
  SELECT EXISTS (
    SELECT 1 FROM public.profiles
    WHERE id = public.current_clerk_user_id() AND role = 'admin'
  );
$$;

CREATE OR REPLACE FUNCTION private.is_intern()
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public, private, extensions, auth, pg_temp
AS $$
  SELECT EXISTS (
    SELECT 1 FROM public.profiles
    WHERE id = public.current_clerk_user_id() AND role IN ('intern', 'admin')
  );
$$;

CREATE OR REPLACE FUNCTION private.assert_admin()
RETURNS void
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public, private, extensions, auth, pg_temp
AS $$
BEGIN
  IF NOT private.is_admin() THEN
    RAISE EXCEPTION 'Alleen admins mogen dit doen';
  END IF;
END;
$$;

GRANT USAGE ON SCHEMA private TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION private.is_admin() TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION private.is_intern() TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION private.assert_admin() TO authenticated, service_role;

DROP FUNCTION IF EXISTS public.is_admin();
DROP FUNCTION IF EXISTS public.is_intern();
DROP FUNCTION IF EXISTS public.assert_admin();

CREATE OR REPLACE FUNCTION public.approve_role_request(request_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, private, extensions, auth, pg_temp
AS $$
DECLARE
  v_user_id text;
BEGIN
  PERFORM private.assert_admin();

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
$$;

CREATE OR REPLACE FUNCTION public.reject_role_request(request_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, private, extensions, auth, pg_temp
AS $$
BEGIN
  PERFORM private.assert_admin();

  UPDATE role_requests
  SET status = 'rejected',
      handled_by = public.current_clerk_user_id(),
      handled_at = now()
  WHERE id = request_id AND status = 'pending';

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Verzoek niet gevonden of al behandeld';
  END IF;
END;
$$;

CREATE OR REPLACE FUNCTION public.approve_reserveringsverzoek(
  verzoek_id uuid,
  note text DEFAULT NULL
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, private, extensions, auth, pg_temp
AS $$
DECLARE
  v reserveringsverzoeken%ROWTYPE;
  new_id uuid;
BEGIN
  PERFORM private.assert_admin();

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
$$;

CREATE OR REPLACE FUNCTION public.reject_reserveringsverzoek(
  verzoek_id uuid,
  note text DEFAULT NULL
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, private, extensions, auth, pg_temp
AS $$
BEGIN
  PERFORM private.assert_admin();

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
$$;

CREATE OR REPLACE FUNCTION public.reject_reserveringsverzoek_reeks(
  verzoek_id uuid,
  note text DEFAULT NULL
)
RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, private, extensions, auth, pg_temp
AS $$
DECLARE
  v_recurrence_id uuid;
  v_count integer;
BEGIN
  PERFORM private.assert_admin();

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
$$;

ALTER TABLE profiles              ENABLE ROW LEVEL SECURITY;
ALTER TABLE rooms                 ENABLE ROW LEVEL SECURITY;
ALTER TABLE reserveringen         ENABLE ROW LEVEL SECURITY;
ALTER TABLE role_requests         ENABLE ROW LEVEL SECURITY;
ALTER TABLE reserveringsverzoeken ENABLE ROW LEVEL SECURITY;
ALTER TABLE support_messages      ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Gebruiker leest eigen profiel"
  ON profiles FOR SELECT TO authenticated
  USING (id = public.current_clerk_user_id());

CREATE POLICY "Gebruiker maakt eigen profiel"
  ON profiles FOR INSERT TO authenticated
  WITH CHECK (id = public.current_clerk_user_id());

CREATE POLICY "Admin leest alle profielen"
  ON profiles FOR SELECT TO authenticated
  USING (private.is_admin());

CREATE POLICY "Admin past profielen aan"
  ON profiles FOR UPDATE TO authenticated
  USING (private.is_admin())
  WITH CHECK (private.is_admin());

CREATE POLICY "Iedereen ziet actieve ruimtes"
  ON rooms FOR SELECT TO authenticated
  USING (active = true OR private.is_admin());

CREATE POLICY "Admin voegt ruimtes toe"
  ON rooms FOR INSERT TO authenticated
  WITH CHECK (private.is_admin());

CREATE POLICY "Admin past ruimtes aan"
  ON rooms FOR UPDATE TO authenticated
  USING (private.is_admin())
  WITH CHECK (private.is_admin());

CREATE POLICY "Admin verwijdert ruimtes"
  ON rooms FOR DELETE TO authenticated
  USING (private.is_admin());

CREATE POLICY "Iedereen ziet reserveringen"
  ON reserveringen FOR SELECT TO authenticated
  USING (true);

CREATE POLICY "Intern en admin mogen reserveren"
  ON reserveringen FOR INSERT TO authenticated
  WITH CHECK (user_id = public.current_clerk_user_id() AND private.is_intern());

CREATE POLICY "Admin maakt reserveringen namens aanvragers"
  ON reserveringen FOR INSERT TO authenticated
  WITH CHECK (private.is_admin());

CREATE POLICY "Gebruiker annuleert eigen reservering"
  ON reserveringen FOR DELETE TO authenticated
  USING (user_id = public.current_clerk_user_id());

CREATE POLICY "Admin verwijdert alle reserveringen"
  ON reserveringen FOR DELETE TO authenticated
  USING (private.is_admin());

CREATE POLICY "Gebruiker ziet eigen rolverzoeken"
  ON role_requests FOR SELECT TO authenticated
  USING (user_id = public.current_clerk_user_id());

CREATE POLICY "Admin ziet alle rolverzoeken"
  ON role_requests FOR SELECT TO authenticated
  USING (private.is_admin());

CREATE POLICY "Extern dient rolverzoek in"
  ON role_requests FOR INSERT TO authenticated
  WITH CHECK (
    user_id = public.current_clerk_user_id()
    AND NOT private.is_intern()
  );

CREATE POLICY "Gebruiker trekt eigen verzoek in"
  ON role_requests FOR DELETE TO authenticated
  USING (user_id = public.current_clerk_user_id() AND status = 'pending');

CREATE POLICY "Admin behandelt rolverzoeken"
  ON role_requests FOR UPDATE TO authenticated
  USING (private.is_admin())
  WITH CHECK (private.is_admin());

CREATE POLICY "Gebruiker ziet eigen reserveringsverzoeken"
  ON reserveringsverzoeken FOR SELECT TO authenticated
  USING (user_id = public.current_clerk_user_id());

CREATE POLICY "Admin ziet alle reserveringsverzoeken"
  ON reserveringsverzoeken FOR SELECT TO authenticated
  USING (private.is_admin());

CREATE POLICY "Iedereen dient reserveringsverzoek in"
  ON reserveringsverzoeken FOR INSERT TO authenticated
  WITH CHECK (user_id = public.current_clerk_user_id());

CREATE POLICY "Gebruiker wijzigt eigen open reserveringsverzoek"
  ON reserveringsverzoeken FOR UPDATE TO authenticated
  USING (user_id = public.current_clerk_user_id() AND status = 'pending')
  WITH CHECK (user_id = public.current_clerk_user_id() AND status = 'pending');

CREATE POLICY "Gebruiker trekt eigen reserveringsverzoek in"
  ON reserveringsverzoeken FOR DELETE TO authenticated
  USING (user_id = public.current_clerk_user_id() AND status = 'pending');

CREATE POLICY "Admin verwijdert reserveringsverzoeken"
  ON reserveringsverzoeken FOR DELETE TO authenticated
  USING (private.is_admin());

CREATE POLICY "Admin behandelt reserveringsverzoeken"
  ON reserveringsverzoeken FOR UPDATE TO authenticated
  USING (private.is_admin())
  WITH CHECK (private.is_admin());

CREATE POLICY "Gebruiker dient vraag klacht of tip in"
  ON support_messages FOR INSERT TO authenticated
  WITH CHECK (user_id = public.current_clerk_user_id());

CREATE POLICY "Gebruiker leest eigen vragen klachten en tips"
  ON support_messages FOR SELECT TO authenticated
  USING (user_id = public.current_clerk_user_id());

CREATE POLICY "Admin leest alle vragen klachten en tips"
  ON support_messages FOR SELECT TO authenticated
  USING (private.is_admin());

CREATE POLICY "Admin behandelt vragen klachten en tips"
  ON support_messages FOR UPDATE TO authenticated
  USING (private.is_admin())
  WITH CHECK (private.is_admin());

REVOKE EXECUTE ON FUNCTION public.approve_role_request(uuid) FROM public, anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.reject_role_request(uuid) FROM public, anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.approve_reserveringsverzoek(uuid, text) FROM public, anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.reject_reserveringsverzoek(uuid, text) FROM public, anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.approve_reserveringsverzoek_reeks(uuid, text) FROM public, anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.reject_reserveringsverzoek_reeks(uuid, text) FROM public, anon, authenticated;

GRANT EXECUTE ON FUNCTION public.approve_role_request(uuid) TO service_role;
GRANT EXECUTE ON FUNCTION public.reject_role_request(uuid) TO service_role;
GRANT EXECUTE ON FUNCTION public.approve_reserveringsverzoek(uuid, text) TO service_role;
GRANT EXECUTE ON FUNCTION public.reject_reserveringsverzoek(uuid, text) TO service_role;
GRANT EXECUTE ON FUNCTION public.approve_reserveringsverzoek_reeks(uuid, text) TO service_role;
GRANT EXECUTE ON FUNCTION public.reject_reserveringsverzoek_reeks(uuid, text) TO service_role;

DROP FUNCTION IF EXISTS public.public_reserveringsverzoeken();
-- ARCHIEF: NIET UITVOEREN. Actuele installatie: SQL/README.md en SQL/basis.sql.
-- Dit bestand bewaart historische ontwikkelstappen, inclusief bekende fouten.
