-- ============================================================
-- WebReserv | 12_public_launch_privacy.sql
-- Privacy- en launch-hardening voor het algemene overzicht.
--
-- Run na: 11_booking_update_and_index.sql
-- ============================================================

BEGIN;

-- GraphQL wordt niet door de frontend gebruikt. Trek clienttoegang in.
DROP EXTENSION IF EXISTS pg_graphql CASCADE;
REVOKE USAGE ON SCHEMA graphql FROM anon, authenticated;
REVOKE EXECUTE ON ALL FUNCTIONS IN SCHEMA graphql FROM anon, authenticated;
ALTER DEFAULT PRIVILEGES IN SCHEMA graphql
  REVOKE EXECUTE ON FUNCTIONS FROM anon, authenticated;
REVOKE USAGE ON SCHEMA graphql FROM public;
REVOKE EXECUTE ON FUNCTION graphql.resolve(text, jsonb, text, jsonb) FROM public, anon, authenticated;
REVOKE EXECUTE ON FUNCTION graphql._internal_resolve(text, jsonb, text, jsonb) FROM public, anon, authenticated;
REVOKE EXECUTE ON FUNCTION graphql.get_schema_version() FROM public, anon, authenticated;
REVOKE EXECUTE ON FUNCTION graphql.increment_schema_version() FROM public, anon, authenticated;
REVOKE EXECUTE ON FUNCTION graphql.comment_directive(text) FROM public, anon, authenticated;
REVOKE EXECUTE ON FUNCTION graphql.exception(text) FROM public, anon, authenticated;

-- Volledige reserveringsrijen bevatten namen en omschrijvingen.
-- Die zijn alleen bedoeld voor de eigenaar en admins.
DROP POLICY IF EXISTS "Iedereen ziet reserveringen" ON public.reserveringen;
DROP POLICY IF EXISTS "Gebruiker leest eigen reserveringen" ON public.reserveringen;
CREATE POLICY "Gebruiker leest eigen reserveringen"
  ON public.reserveringen FOR SELECT TO authenticated
  USING (
    user_id = public.current_clerk_user_id()
    OR private.is_admin()
  );

-- Geschoonde bevestigde reserveringen voor het algemene overzicht.
-- Eigen reserveringen worden hier uitgesloten; die leest de frontend
-- via de normale tabelpolicy, zodat wijzigen/annuleren blijft werken.
CREATE OR REPLACE FUNCTION public.public_reserveringen_overzicht()
RETURNS TABLE (
  room_id text,
  date date,
  start_time time without time zone,
  end_time time without time zone,
  status text
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public, private, extensions, auth, pg_temp
AS $$
  SELECT r.room_id, r.date, r.start_time, r.end_time, 'confirmed'::text AS status
  FROM public.reserveringen r
  WHERE r.user_id <> public.current_clerk_user_id();
$$;

-- Geschoonde openstaande reserveringsverzoeken voor het algemene overzicht.
DROP FUNCTION IF EXISTS private.public_reserveringsverzoeken();

CREATE OR REPLACE FUNCTION public.public_reserveringsverzoeken()
RETURNS TABLE (
  room_id text,
  date date,
  start_time time without time zone,
  end_time time without time zone,
  status text
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public, private, extensions, auth, pg_temp
AS $$
  SELECT rv.room_id, rv.date, rv.start_time, rv.end_time, rv.status
  FROM public.reserveringsverzoeken rv
  WHERE rv.status = 'pending';
$$;

REVOKE EXECUTE ON FUNCTION public.public_reserveringen_overzicht() FROM public, anon;
REVOKE EXECUTE ON FUNCTION public.public_reserveringsverzoeken() FROM public, anon;
GRANT EXECUTE ON FUNCTION public.public_reserveringen_overzicht() TO authenticated;
GRANT EXECUTE ON FUNCTION public.public_reserveringsverzoeken() TO authenticated;

-- Private helpers zijn alleen nodig voor authenticated policies en service_role.
REVOKE USAGE ON SCHEMA private FROM public, anon;
REVOKE EXECUTE ON ALL FUNCTIONS IN SCHEMA private FROM public, anon;
ALTER DEFAULT PRIVILEGES IN SCHEMA private
  REVOKE EXECUTE ON FUNCTIONS FROM public, anon;

COMMIT;
-- ARCHIEF: NIET UITVOEREN. Actuele installatie: SQL/README.md en SQL/basis.sql.
-- Dit bestand bewaart historische ontwikkelstappen, inclusief bekende fouten.
