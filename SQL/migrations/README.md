# Toekomstige migraties

Na heropbouw geen reset of basis opnieuw uitvoeren. Maak per wijziging een migratie
met het actuele Supabase CLI-commando `supabase migration new` (controleer eerst
`--help`). Bewaar de gegenereerde migratie in de repository, test lokaal en vraag
goedkeuring vóór live toepassing. Registreer live DDL via `apply_migration` en
controleer daarna migratiehistorie en `SQL/verify.sql`.

De eenmalige heropbouw wordt na goedkeuring als één migratie geregistreerd. De
inhoud bestaat uit gecontroleerde reset, basis, ruimtes en adminherstel.
Het admin-ID wordt niet in de openbare repository opgeslagen.
