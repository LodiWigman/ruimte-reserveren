-- ============================================================
-- WebReserv | 09_security_hardening_after_lints.sql
-- Herstelt de app-flow na het dichtzetten van SECURITY DEFINER RPC's.
--
-- Run na de security-lint query die de RPC's heeft afgesloten/verplaatst.
-- De frontend verwerkt admin-acties daarna via normale tabeloperaties onder RLS.
-- ============================================================

BEGIN;

CREATE SCHEMA IF NOT EXISTS private;
CREATE SCHEMA IF NOT EXISTS extensions;

ALTER EXTENSION btree_gist SET SCHEMA extensions;

ALTER FUNCTION public.current_clerk_user_id()
  SET search_path = public, auth, pg_temp;

GRANT USAGE ON SCHEMA private TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION private.is_admin() TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION private.is_intern() TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION private.assert_admin() TO authenticated, service_role;

DROP FUNCTION IF EXISTS private.public_reserveringsverzoeken();
DROP FUNCTION IF EXISTS public.public_reserveringsverzoeken();

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

DROP POLICY IF EXISTS "Admin maakt reserveringen namens aanvragers" ON reserveringen;
CREATE POLICY "Admin maakt reserveringen namens aanvragers"
  ON reserveringen FOR INSERT TO authenticated
  WITH CHECK (private.is_admin());

DROP POLICY IF EXISTS "Gebruiker wijzigt eigen open reserveringsverzoek" ON reserveringsverzoeken;
CREATE POLICY "Gebruiker wijzigt eigen open reserveringsverzoek"
  ON reserveringsverzoeken FOR UPDATE TO authenticated
  USING (user_id = public.current_clerk_user_id() AND status = 'pending')
  WITH CHECK (user_id = public.current_clerk_user_id() AND status = 'pending');

DROP POLICY IF EXISTS "Admin behandelt reserveringsverzoeken" ON reserveringsverzoeken;
CREATE POLICY "Admin behandelt reserveringsverzoeken"
  ON reserveringsverzoeken FOR UPDATE TO authenticated
  USING (private.is_admin())
  WITH CHECK (private.is_admin());

DROP POLICY IF EXISTS "Admin behandelt rolverzoeken" ON role_requests;
CREATE POLICY "Admin behandelt rolverzoeken"
  ON role_requests FOR UPDATE TO authenticated
  USING (private.is_admin())
  WITH CHECK (private.is_admin());

COMMIT;
-- ARCHIEF: NIET UITVOEREN. Actuele installatie: SQL/README.md en SQL/basis.sql.
-- Dit bestand bewaart historische ontwikkelstappen, inclusief bekende fouten.
