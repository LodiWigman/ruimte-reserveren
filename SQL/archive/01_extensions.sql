-- ============================================================
-- WebReserv | 01_extensions.sql
-- Nodige PostgreSQL/Supabase uitbreidingen.
-- ============================================================

CREATE SCHEMA IF NOT EXISTS extensions;

CREATE EXTENSION IF NOT EXISTS btree_gist WITH SCHEMA extensions;
-- ARCHIEF: NIET UITVOEREN. Actuele installatie: SQL/README.md en SQL/basis.sql.
-- Dit bestand bewaart historische ontwikkelstappen, inclusief bekende fouten.
