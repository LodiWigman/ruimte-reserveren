-- ============================================================
-- WebReserv | 13_import_reserveringen.sql
-- Admin bulk-import voor reserveringen uit Excel, CSV en ICS.
--
-- Run na: 12_public_launch_privacy.sql
-- ============================================================

BEGIN;

CREATE OR REPLACE FUNCTION public.import_reserveringen(import_items jsonb)
RETURNS TABLE (
  row_index integer,
  booking_id uuid,
  status text,
  message text
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, private, extensions, auth, pg_temp
AS $$
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
$$;

REVOKE EXECUTE ON FUNCTION public.import_reserveringen(jsonb) FROM public, anon;
GRANT EXECUTE ON FUNCTION public.import_reserveringen(jsonb) TO authenticated;

COMMIT;
