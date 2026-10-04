# Toekomstige migraties

**Publicatie na eindgoedkeuring van het [actuele overzicht](../../docs/PUBLICATIEKLAAR-2026-10-01.md).**
De bestaande Clerk-testomgeving
blijft gebruikt. De onderstaande nog niet uitgevoerde Connectr-migratie bevat ook
bezettingsprivacy, quota, auditregistratie, sessie-intrekking en accountblokkade.
Zij vereist ondertekende Clerk-claims `sub`, `sid`, `iss` en `azp`. De private
`trusted_auth`-tabel staat voorlopig op de bestaande development-uitgever en het
officiële Vercel-adres. Test- en productieconfiguratie moeten bewust worden ingericht
en met echte tokens getest; voeg geen wildcard of ontbrekende-claim-uitzondering toe.
Een overstap naar Clerk-productie kan account-ID's veranderen: bepaal en test eerst
de mapping, zodat bestaande boekingen en beheerdersrechten behouden blijven.

Voorbereid, nog niet live: `20260929192403_connectr_profiles_conversations.sql`.
Vereist de bestaande `reservation_workflows`-structuur. De bestandsversie is
gegenereerd met Supabase CLI 2.117.0. De migratie bevat één transactie en behoudt
de oude gesprekken en reacties. Lees vóór uitvoering
[CONNECTR-OPLEVERING](../../docs/CONNECTR-OPLEVERING.md); de nieuwe website en
database-API moeten samen worden gepubliceerd.

Na heropbouw geen reset of basis opnieuw uitvoeren. Maak per wijziging een migratie
met het actuele Supabase CLI-commando `supabase migration new` (controleer eerst
`--help`). Bewaar de gegenereerde migratie in de repository, test lokaal en vraag
goedkeuring vóór live toepassing. Registreer live DDL via `apply_migration` en
controleer daarna migratiehistorie en `SQL/verify.sql`.

De eenmalige heropbouw wordt na goedkeuring als één migratie geregistreerd. De
inhoud bestaat uit gecontroleerde reset, basis, ruimtes en adminherstel.
Het admin-ID wordt niet in de openbare repository opgeslagen.
