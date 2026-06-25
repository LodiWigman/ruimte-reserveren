-- ============================================================
-- WebReserv | 04_functions.sql
-- Hulpfuncties en admin-acties.
-- Run na: 03_indexes.sql
-- ============================================================

CREATE OR REPLACE FUNCTION public.is_admin()
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT EXISTS (
    SELECT 1 FROM profiles
    WHERE id = auth.uid() AND role = 'admin'
  );
$$;

CREATE OR REPLACE FUNCTION public.is_intern()
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT EXISTS (
    SELECT 1 FROM profiles
    WHERE id = auth.uid() AND role IN ('intern', 'admin')
  );
$$;

CREATE OR REPLACE FUNCTION public.assert_admin()
RETURNS void
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF NOT public.is_admin() THEN
    RAISE EXCEPTION 'Alleen admins mogen dit doen';
  END IF;
END;
$$;

CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  INSERT INTO profiles (id, display_name)
  VALUES (
    NEW.id,
    COALESCE(NEW.raw_user_meta_data->>'display_name', split_part(NEW.email, '@', 1))
  )
  ON CONFLICT (id) DO NOTHING;

  RETURN NEW;
END;
$$;

CREATE OR REPLACE FUNCTION public.public_reserveringsverzoeken()
RETURNS TABLE (
  room_id text,
  date date,
  start_time time,
  end_time time,
  status text
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT rv.room_id, rv.date, rv.start_time, rv.end_time, rv.status
  FROM reserveringsverzoeken rv
  WHERE rv.status = 'pending';
$$;

CREATE OR REPLACE FUNCTION public.approve_role_request(request_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user_id uuid;
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
      handled_by = auth.uid(),
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
SET search_path = public
AS $$
BEGIN
  PERFORM public.assert_admin();

  UPDATE role_requests
  SET status = 'rejected',
      handled_by = auth.uid(),
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
SET search_path = public
AS $$
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
      handled_by = auth.uid(),
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
SET search_path = public
AS $$
BEGIN
  PERFORM public.assert_admin();

  UPDATE reserveringsverzoeken
  SET status = 'rejected',
      handled_by = auth.uid(),
      handled_at = now(),
      admin_note = note
  WHERE id = verzoek_id AND status = 'pending';

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Verzoek niet gevonden of al behandeld';
  END IF;
END;
$$;

CREATE OR REPLACE FUNCTION public.approve_reserveringsverzoek_reeks(
  verzoek_id uuid,
  note text DEFAULT NULL
)
RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
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
$$;

CREATE OR REPLACE FUNCTION public.reject_reserveringsverzoek_reeks(
  verzoek_id uuid,
  note text DEFAULT NULL
)
RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
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
      handled_by = auth.uid(),
      handled_at = now(),
      admin_note = note
  WHERE recurrence_id = v_recurrence_id AND status = 'pending';

  GET DIAGNOSTICS v_count = ROW_COUNT;
  RETURN v_count;
END;
$$;

REVOKE EXECUTE ON FUNCTION public.public_reserveringsverzoeken() FROM anon;
GRANT EXECUTE ON FUNCTION public.public_reserveringsverzoeken() TO authenticated;
