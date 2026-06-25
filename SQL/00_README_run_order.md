# WebReserv SQL volgorde

Run deze bestanden in Supabase SQL Editor in deze volgorde:

1. `01_extensions.sql`
2. `02_tables.sql`
3. `03_indexes.sql`
4. `04_functions.sql`
5. `05_triggers.sql`
6. `06_policies.sql`

Belangrijk:

- Deze bestanden zijn bedoeld voor een lege database.
- Ze bevatten geen `DROP TABLE`, zodat je niet per ongeluk data wist.
- Als een stap faalt, stop dan en los eerst die fout op voordat je verdergaat.
- `sql_file.txt` mag blijven bestaan als totaaloverzicht, maar deze map is netter om handmatig te runnen.
