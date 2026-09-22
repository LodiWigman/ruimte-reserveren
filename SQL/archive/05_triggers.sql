-- ============================================================
-- WebReserv | 05_triggers.sql
-- Automatische acties op databasegebeurtenissen.
-- Run na: 04_functions.sql
-- ============================================================

DROP TRIGGER IF EXISTS on_auth_user_created ON auth.users;

CREATE TRIGGER on_auth_user_created
  AFTER INSERT ON auth.users
  FOR EACH ROW EXECUTE FUNCTION public.handle_new_user();
-- ARCHIEF: NIET UITVOEREN. Actuele installatie: SQL/README.md en SQL/basis.sql.
-- Dit bestand bewaart historische ontwikkelstappen, inclusief bekende fouten.
