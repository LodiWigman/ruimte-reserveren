-- ============================================================
-- WebReserv | 11_booking_update_and_index.sql
-- Herstelt wijzigen van eigen reserveringen voor internen/admins
-- en voegt een ontbrekende foreign-key index toe.
--
-- Run na: 10_data_api_grants.sql
-- ============================================================

BEGIN;

DROP POLICY IF EXISTS "Gebruiker wijzigt eigen reservering" ON public.reserveringen;
CREATE POLICY "Gebruiker wijzigt eigen reservering"
  ON public.reserveringen FOR UPDATE TO authenticated
  USING (
    user_id = public.current_clerk_user_id()
    AND private.is_intern()
  )
  WITH CHECK (
    user_id = public.current_clerk_user_id()
    AND private.is_intern()
  );

CREATE INDEX IF NOT EXISTS idx_reserveringsverzoeken_room_id
  ON public.reserveringsverzoeken (room_id);

COMMIT;
-- ARCHIEF: NIET UITVOEREN. Actuele installatie: SQL/README.md en SQL/basis.sql.
-- Dit bestand bewaart historische ontwikkelstappen, inclusief bekende fouten.
