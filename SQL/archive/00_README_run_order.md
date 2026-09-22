# WebReserv SQL volgorde

Run deze bestanden in Supabase SQL Editor in deze volgorde:

1. `01_extensions.sql`
2. `02_tables.sql`
3. `03_indexes.sql`
4. `04_functions.sql`
5. `05_triggers.sql`
6. `06_policies.sql`
7. `07_support_messages.sql` voor vragen, klachten en verbetertips
8. `08_clerk_auth_migration.sql` als je Clerk gebruikt in plaats van Supabase Auth
9. `09_security_hardening_after_lints.sql` na de security-lint aanpassingen
10. `10_data_api_grants.sql` zodat de frontend via Supabase Data API bij de RLS-tabellen kan
11. `11_booking_update_and_index.sql` zodat internen eigen reserveringen kunnen wijzigen en de verzoeken-FK geindexeerd is
12. `12_public_launch_privacy.sql` verbergt namen/omschrijvingen in het openbare overzicht, toont open verzoeken geschoond en schakelt GraphQL uit voor clientrollen
13. `13_import_reserveringen.sql` voegt de admin bulk-importfunctie toe voor reserveringen uit Excel, CSV en ICS

Belangrijk:

- Deze bestanden zijn bedoeld voor een lege database.
- Ze bevatten geen `DROP TABLE`, zodat je niet per ongeluk data wist.
- Als een stap faalt, stop dan en los eerst die fout op voordat je verdergaat.
- `sql_file.txt` mag blijven bestaan als totaaloverzicht, maar deze map is netter om handmatig te runnen.
- Voor Clerk moet je ook in Supabase de Clerk provider activeren en in `github_index.html` de `CLERK_PUBLISHABLE_KEY` invullen.
- RLS bepaalt welke rijen zichtbaar of wijzigbaar zijn. De grants in `10_data_api_grants.sql` bepalen alleen dat ingelogde gebruikers de tabellen via de Data API mogen bereiken.
# ARCHIEF — deze uitvoervolgorde is vervallen. Zie ../README.md.
