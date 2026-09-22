# Uitgevoerde herstelrelease — 22 september 2026

De gebruiker heeft de voorbereide versie expliciet goedgekeurd, Vercel als actieve
host bevestigd en gevraagd geen Vercel-controle uit te voeren. GitHub `main` is de
publicatiebron. De website blijft in de bestaande Clerk-testomgeving.

## Database

Supabase `han-reserveringen`, project `oappvdfjyvbmvqrjvnmv`:
migratie **20260922131921 — han_clerk_rebuild** is geslaagd.

Vóór uitvoering zijn de zes applicatietabellen en het objectcatalogusrapport opnieuw
lokaal opgeslagen buiten de repository. Gegevens, kolommen, constraints, functies,
policies, indexen en grants kwamen overeen met de onderzochte uitgangssituatie.
De heropbouw is als één atomair DO-statement uitgevoerd; het exacte uitvoerbestand
is aanvullend op PostgreSQL 17.6 getest op volledig terugdraaien en succesvol herstel.

Na uitvoering gecontroleerd:

- Zes applicatietabellen, alle zes met RLS en één leespolicy.
- Alleen SELECT voor authenticated; geen directe browsermutaties en geen anonieme tabelgrants.
- Dertien publieke applicatie-RPC's, alleen uitvoerbaar door authenticated,
  met lege search_path en de gecontroleerde rol-/eigenaarscontroles.
- Interne schrijfhulpjes niet uitvoerbaar door anon/authenticated.
- Overlapconstraint en datum-, tijd-, tekst- en verwijzingscontroles aanwezig.
- Achttien ruimtes teruggezet: zeventien actief, W0.02 inactief.
- Eén profiel: het gecontroleerde adminprofiel lodi.wigman met hetzelfde Clerk-ID.
- Reserveringen, reserveringsverzoeken, rolverzoeken en supportberichten leeg.
- De oude kapotte applicatiefuncties zijn verwijderd; de eerdere migratiehistorie blijft bewaard.

## Advisors

Geen RLS- of openbare-anonieme-toegangswaarschuwing aangetroffen.
Wel dertien waarschuwingen over bewust uitvoerbare SECURITY DEFINER-RPC's:
dit is de gekozen gecontroleerde API, niet een algemene toekenning van adminrechten.
Rechten en toegangscontroles zijn afzonderlijk gecontroleerd en lokaal getest.
Zie [uitleg van deze waarschuwing](https://supabase.com/docs/guides/database/database-linter?lint=0029_authenticated_security_definer_function_executable).

Drie informatieve performancebevindingen betreffen niet-geïndexeerde `handled_by`-
verwijzingen. De huidige API verwijdert geen profielen en zoekt niet op deze kolommen;
bij groter gebruik of een profielverwijderfunctie opnieuw beoordelen.
Zie [foreign-key-indexadvies](https://supabase.com/docs/guides/database/database-linter?lint=0001_unindexed_foreign_keys).
Zes indexen worden nog als ongebruikt gemeld in de net opnieuw opgebouwde database.
Behoud integriteitsindexen en beoordeel gebruik pas met representatieve belasting:
[indexadvies](https://supabase.com/docs/guides/database/database-linter?lint=0005_unused_index).

## Publicatie en testgrens

Onderhoudspagina eerst op `main` gezet in commit
`af587791e89ef96d71db2d173d29586652cd11e0`. Daarna volgt deze definitieve release.
De definitieve commit is te vinden in de GitHub-geschiedenis bij dit bestand.
Er wordt niet apart naar GitHub Pages gepubliceerd en niets aan hostinginstellingen gewijzigd.
Een eventueel al bestaande automatische Pages-workflow is niet uitgezet.

Lokale controles: 17 frontend-, 19 database-, 2 reset-/herstelcontroles, plus
2 uitgebreide desktop-/mobielscenario's en de aanvullende exacte uitvoerbestandcontrole.
Clerk-sessies zijn in browsertests nagebootst. Echte login, tokenverversing en de
gehoste website vereisen nog de eigen-accountproeven. Vercel is op verzoek niet
gecontroleerd; een GitHub-publicatie wordt dus niet als geverifieerde hosting geclaimd.

Zie [jouw volgende stappen](VOLGENDE-STAPPEN.md) en [volledige verificatie](VERIFICATIE.md).
