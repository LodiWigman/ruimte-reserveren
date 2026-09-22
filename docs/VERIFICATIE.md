# Verificatie — 22 september 2026

## Geslaagd

Uitgevoerd op de voorbereide versie, lokaal op Windows met Node.js 24.19.0,
PostgreSQL 17.6 en Edge/Playwright 1.62.1. Er zijn geen aanvallen, accountpromoties
of testmutaties op de live Supabase-database uitgevoerd.

| Controle | Resultaat |
| --- | --- |
| `tests/frontend.mjs` | 17 scenario's: syntax, strikte datums/tijden, maandultimo/schrikkeldagen, DST, CSV met regeleinden/quotes, ICS tijdzone/herhaling/EXDATE/UNTIL, weigering onondersteunde ICS, reeks-ID, importoverlap, nul-resultaat, 1201 rijen met kleinere serverpagina's |
| `tests/database.mjs` | 19 scenario's op een lege PostgreSQL 17.6-database: zes RLS-tabellen, grants, gast/extern/intern/admin, geen zelfpromotie, eigenaarschap/privacy, boeking/verzoek/wijziging/annulering, goedkeuring/afwijzing, rollen, support, rollback van reeksacties/import en gelijktijdige aanvragen |
| `tests/reset.mjs` | 2 controles: reconstrueren oude live applicatiestructuur, complete reset/basis/ruimtes/adminherstel, rollback bewaart oude gegevens, aparte systeemtabel blijft bestaan |
| `tests/browser.mjs` | 2 uitgebreide scenario's op 1365×1000 en 390×844: gast, testlogin, extern verzoek, admin goedkeuring, vraag/reactie, CSV-import, blokkeren dubbele import, Excel-parser, intern boeken/wijzigen, logout, escaping ruimte-ID en geen horizontale overflow |
| Code-review | Aangeraakte callers, gevoelige API-invoer, autorisatie, nul-resultaten, transacties, escaping en obsolete functies gecontroleerd; geen directe browsermutaties meer |
| Git-controle | Diff gecontroleerd op whitespacefouten; alleen voorbereide release in aparte lokale checkout |
| Openbare infrastructuur | De eerder gecontroleerde Pages-kopie kwam overeen met GitHub. De gebruiker heeft daarna Vercel bevestigd als actieve host en gevraagd Vercel niet te controleren. Vastgezette Clerk-scripts geven HTTP 200 |

De browser gebruikt de echte `index.html`, Supabase SDK en SheetJS. Alle HTTP-aanroepen
worden lokaal afgehandeld. Clerk-sessies en de HTTP-naar-SQL-vertaling zijn testdubbels.
Dit bewijst de interactie tussen schermen en databasefuncties, maar niet de werkelijke
Clerk-tokenvalidatie of alle details van de beheerde PostgREST-laag.

De reconstructiefixture bevat de aangetroffen tabellen, constraints, applicatiefuncties,
policies en triggers. Zij is geen volledige Supabase-systeemkopie. De lege opbouw
en grants zijn bovendien getest met ruime standaard Supabase-achtige default grants,
zodat de expliciete intrekking van rechten daadwerkelijk wordt gecontroleerd.

## Advisorbevindingen

Live meldde de security-advisor drie waarschuwingen voor aangemelde gebruikers die
SECURITY DEFINER-RPC's kunnen uitvoeren. De kapotte admincontrole in de oude import
was een echte fout. Dat de geschoonde bezettingsfunctie onder gecontroleerde
voorwaarden uitvoerbaar is, is op zichzelf geen fout.

De nieuwe gecontroleerde RPC's gebruiken diezelfde noodzakelijke bevoegdheidsgrens:
strikte rollen/eigenaarschap, lege search_path, beperkte uitvoerrechten en geen directe
tabelwrites. Bij de live release moeten de advisors opnieuw worden gelezen en per
functie beoordeeld. Zie [Supabase definer-lint](https://supabase.com/docs/guides/database/database-linter?lint=0029_authenticated_security_definer_function_executable).

Performancewaarschuwingen betroffen onder meer ongebruikte indexen en meerdere
permissive policies. Ongebruikte indexen zijn bij deze kleine, nog niet gebruikte
database geen reden om integriteitsindexen te verwijderen. De nieuwe basis heeft
één leespolicy per tabel en gerichte datum/eigenaar/reeks-indexen. Zie
[indexadvies](https://supabase.com/docs/guides/database/database-linter?lint=0005_unused_index).

## Niet vastgesteld / resterende grenzen

- Echte Clerk-login, Supabase-tokenvalidatie, sessievernieuwing en de uiteindelijke
  live Data API moeten na goedkeuring met het eigen account worden getest.
- Geen Clerk-productiedomein of productieomgeving beschikbaar. De voorbereide release
  blijft daarom een testpublicatie. Het productiepad staat in UITVOEREN.md.
- Geen omvangrijke belastingtest, onafhankelijke pentest of volledige toegankelijkheidsaudit.
  De korte globale schrijflock is passend voor de huidige schaal, maar moet bij
  veel gelijktijdig gebruik worden gemeten. De database blijft overlap afdwingen.
- Inlezen van lijsten is gepagineerd, maar niet één gezamenlijke snapshot over alle
  HTTP-pagina's. Definitieve beslissingen worden daarom altijd in de database genomen.
- Geen onbegrensde recurrence-engine: maximaal 520 momenten; gedocumenteerde
  niet-ondersteunde ICS-gevallen worden afgewezen. Import is geen agendasynchronisatie.
- Geen algemene idempotentiesleutel voor elke mutatie. Bij een onduidelijke netwerkfout
  eerst verversen/controleren. Dubbele bevestigde tijden worden databasebreed verhinderd.
- Een ingetrokken of verwijderd Clerk-account kan een reeds uitgegeven token nog tot
  zijn vervaltijd hebben; deze release introduceert geen extra revocatiedienst.
- Externe scripts/fonts blijven netwerkafhankelijk; gebruikte JavaScript-versies zijn
  vastgezet. Er zijn geen beheersleutels toegevoegd aan de frontend.

## Eigen-login-praktijktest na publicatie

1. Open de eigen Vercel-website in een nieuw venster, log in en controleer admin-tab/rol.
2. Boek een vrije tijd, wijzig deze en annuleer alleen die gebeurtenis.
3. Maak een korte reeks; wijzig/annuleer vanaf het tweede moment en controleer dat
   het eerste blijft staan. Test ook een conflict en een geweigerde reeksgoedkeuring.
4. Gebruik een apart extern testaccount: profiel is extern, alleen eigen details,
   verzoek indienen/wijzigen/intrekken en interne rol aanvragen. Behandel als admin.
5. Dien een vraag in, antwoord als admin en controleer de reactie bij de gebruiker.
6. Importeer een klein, gecontroleerd bestand, probeer hetzelfde bestand opnieuw en
   controleer dat er geen tweede boeking ontstaat. Test een ICS uit je eigen Outlook.
7. Controleer dezelfde handelingen mobiel, ververs de pagina en test uitloggen/herinloggen.
8. Controleer bij gebruik dat Vercel de bedoelde release toont (bijvoorbeeld de nieuwe supportreactie).
