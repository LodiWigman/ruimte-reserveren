-- ============================================================
-- WebReserv | 10_data_api_grants.sql
-- Maakt de RLS-tabellen bereikbaar via Supabase Data API.
--
-- Run na: 09_security_hardening_after_lints.sql
--
-- Supabase vereist naast RLS-policies ook expliciete GRANTs voor
-- rollen die tabellen via supabase-js / PostgREST moeten gebruiken.
-- RLS blijft bepalen welke rijen gebruikers daadwerkelijk mogen zien
-- of wijzigen.
-- ============================================================

BEGIN;

GRANT USAGE ON SCHEMA public TO authenticated;

GRANT SELECT, INSERT, UPDATE, DELETE ON TABLE public.profiles TO authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON TABLE public.rooms TO authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON TABLE public.reserveringen TO authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON TABLE public.reserveringsverzoeken TO authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON TABLE public.role_requests TO authenticated;
GRANT SELECT, INSERT, UPDATE ON TABLE public.support_messages TO authenticated;

COMMIT;
-- ARCHIEF: NIET UITVOEREN. Actuele installatie: SQL/README.md en SQL/basis.sql.
-- Dit bestand bewaart historische ontwikkelstappen, inclusief bekende fouten.
