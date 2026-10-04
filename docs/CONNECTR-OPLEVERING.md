# HAN@Connectr — voorbereide oplevering

**Actuele vrijgaveafspraak:** zie [PUBLICATIEKLAAR-2026-10-01](PUBLICATIEKLAAR-2026-10-01.md).
Clerk development blijft op verzoek gebruikt.
De onderstaande veiligheidsstatus en hashes zijn historisch; de functionele scope
blijft behouden. Het actuele overzicht bepaalt de definitieve publicatievolgorde.

**Beveiligingsaanscherping 1 oktober 2026: nog geen positief productieadvies.**
Lees eerst [het actuele publicatieoverzicht](PUBLICATIEKLAAR-2026-10-01.md). Na de oorspronkelijke
beoordeling zijn applicatie en de nog niet gepubliceerde migratie verder beveiligd.
Onderstaande functionele oplevering is geen beveiligingsvrijgave. De oude hashes en
testaantallen hieronder horen bij de eerdere voorbereiding; het publicatieoverzicht
en de releaseverificatie leggen de nieuwe stand vast.

Status op 1 oktober 2026: lokaal geïmplementeerd, gereviewd en getest. Niets uit deze release
is gepusht, gepubliceerd of op de live database toegepast. Het plan is goedgekeurd;
publicatie en bijbehorende live wijzigingen vragen afzonderlijke eindgoedkeuring.

## Wat verandert

- **Mijn profiel:** verplichte voor- en achternaam. Nieuwe accounts krijgen geen
  uit e-mail afgeleide naam. Bestaande namen blijven bewaard als referentie, maar
  worden niet automatisch als bewust ingevuld aangemerkt. De gebruiker bevestigt
  expliciet de naam. Toekomstige reserveringen en open verzoeken volgen deze naam;
  afgelopen reserveringen behouden hun historische naam. Rechten volgen account-ID's.
- **Namens iemand boeken:** admins zoeken bestaande accounts op naam of exact ID.
  Deze reserveringen zijn direct bevestigd. Een gast zonder account krijgt een
  zichtbare gastnaam en blijft eigendom van de admin. Maker en eigenaar worden
  afzonderlijk opgeslagen. Bestaande makers worden niet achteraf verzonnen.
- **Overdracht:** controlevenster met beide accounts, momenten, aantallen en
  gevolgen. Los moment of dit en volgende momenten; eerdere momenten blijven
  staan. Open verzoeken blijven open. De nieuwe eigenaar krijgt persoonlijke
  toegang; de vorige verliest die. Beide betrokkenen krijgen een melding, behalve
  degene die zelf de actie uitvoert. Overdracht wordt vastgelegd met uitvoerder en tijd.
- **NL/EN:** onthouden taalkeuze, vertaalde interface en Clerk-vensters, officiële
  HAN-afbeelding en de titel HAN@Connectr. Vrije tekst blijft letterlijk behouden.
  Het ongewijzigde logo is lokaal opgenomen uit
  <https://www.han.nl/images/logo/han_university.svg>.
- **Gesprekken:** vraag, klacht of tip; anoniem of met profielnaam en optioneel
  contactadres. Berichten worden toegevoegd aan de historie. Anonieme identiteit
  ontbreekt ook in de antwoorden van de API en in meldingen aan admins. De website
  verstuurt geen e-mail. Adminreacties tonen de naam van de beheerder.
- **Archief:** reageren op afgehandeld heropent de case; admins kunnen afgehandelde
  cases archiveren. Het archief bewaart de historie en is alleen leesbaar totdat
  een admin heropent. Iedere gebruiker ziet uitsluitend de eigen cases.
- **Meldingen en gezamenlijk beheer:** opgeslagen ongelezenstatus per gebruiker,
  belletje en links naar toegankelijke items. Alle admins delen hetzelfde werk.
  Actieve schermen verversen iedere 15 seconden; ingevulde formulieren blijven
  behouden. Locks, versievergelijkingen en controles op status voorkomen dubbele
  verwerking en het overschrijven van verouderde bewerkingen. Lezen handelt niets af.

## Gegevens en compatibiliteit

De onderzochte publicatie is GitHub `LodiWigman/ruimte-reserveren`, `main`, commit
`75ab09f61c4dd534550db8380603d70b12e91804`. Bij hercontrole op 1 oktober 2026
was dit nog dezelfde commit. Supabase-project: `oappvdfjyvbmvqrjvnmv`.
De live migratiehistorie eindigt op `20260924091138 reservation_workflows`.
De huidige `SQL/basis.sql` bevat die workflowwijzigingen al.

Gerichte vervolgmigratie:
`SQL/migrations/20260929192403_connectr_profiles_conversations.sql`.
Deze voegt profielnamen, makerinformatie, meldingen, overdrachtshistorie,
gespreksberichten en gelezenstatus toe. De bestaande meldingentabel verhuist
naar `han_private`; originele rijen, adminreacties, status en bekende afzenders
en tijdstippen blijven behouden. Onbekende tijdstippen blijven onbekend.
Oude meldingen worden anoniem en niet ingedeeld; afgehandeld wordt niet automatisch
gearchiveerd. Een afwijkende oude reserveringsnaam is geen bewijs van een gastboeking
en wordt dus niet automatisch als gastuitzondering vastgelegd.

Alle identiteitsgevoelige tabellen staan buiten de blootgestelde API. Browserrollen
hebben geen directe rechten daarop. Alleen gecontroleerde functies retourneren
toegestane velden. Profiel- en reserveringsrechten blijven op account-ID gebaseerd.
Geen nieuwe geheime sleutels of uitgebreidere browserrechten.

De nieuwe API verandert `han_edit` en `han_decide_request` (verwachte rijversies)
en vervangt de oude ondersteuning door gesprekken. Een oude, reeds geopende
browser kan daarom om verversen vragen. Het oude formulier mag geen reacties meer
overschrijven. Frontend en database moeten als één release overgaan.

## Controles en beperkingen

De tests gebruiken uitsluitend lokale PostgreSQL en fictieve accounts. Het browser-
onderzoek gebruikt de echte HTML, Supabase SDK en vastgezette Clerk-taalpakketten,
met een nagebootste Clerk-sessie en lokaal afgehandelde netwerkverzoeken.

Geslaagd op 29 september–1 oktober 2026: 22 frontendscenario's, 19 databasebasisscenario's,
10 workflowregressies, 2 historische herstelcontroles en 18 Connectr-scenario's.
De Connectr-tests controleren onder meer afgebroken migratie zonder gedeeltelijke
wijzigingen, behoud van onbekende historische afzenders/tijdstippen, ontbrekende
namen, gastboekingen, overdrachten en concurrerende admins, externe wijzigingsregels,
anonimiteit via directe API-aanroepen, archiveren/heropenen en persoonlijke
gelezenstatus. Ook een nieuw binnengekomen bericht blijft ongelezen wanneer alleen
de eerder opgehaalde historie gelezen is.

De volledige browsercontrole is op 1 oktober geslaagd op desktop (1365 × 1000)
en mobiel (390 × 844), inclusief profielaanvulling, naamwijziging, boeken namens
accounts/gasten, overdracht, gesprekken, archiveren/heropenen, meldingen, NL/EN,
behoud van vrije tekst en conceptvelden/focus, import, reeksen en externe
wijzigingsregels. Geen horizontale overloop of JavaScript-fouten in deze stromen.
De screenshots zijn visueel gecontroleerd. Ook de aparte browserregressie voor
Nederlandse/Engelse native validatiemeldingen en het wissen van achterhaalde
veldfouten slaagt. Totaal: 71 logica-/databasescenario's, twee volledige
viewportscenario's en een aanvullende validatiecontrole. De uiteindelijke
testruns sluiten met exitcode 0; `git diff --check` meldt geen fouten.

De gerichte review omvatte accountrechten, databasegrants, anonimiteit in API-
antwoorden, HTML-escaping, behoud van historie, transacties en gelijktijdige
verwerking. Verholpen bevindingen zijn afgedekt door de bovengenoemde tests.
Dit is een review van deze wijzigingen, geen certificering van het hele platform.

Registratie bij de echte Clerk-dienst, echte tokenverificatie door Supabase en de
gehoste Vercel-versie zijn niet door de lokale tests bewezen. De bestaande Clerk-
testomgeving blijft gebruikt. De publiek leesbare configuratie heeft voor- en
achternaam ingeschakeld maar nog niet verplicht. Die twee velden moeten bij de
goedgekeurde release verplicht worden gezet in Clerk. De applicatie blokkeert
onvolledige profielen daarnaast zelf en de database weigert hun reserveringen en
verzoeken. Profielwijzigingen worden ook naar Clerk doorgestuurd; bij een mislukte
Clerk-synchronisatie blijft de applicatienaam leidend en krijgt de gebruiker uitleg.

Clerk is vastgezet op `clerk-js 6.32.1`, UI `1.33.1` en taalbestanden `4.20.0`.
Na initialisatie negeert Clerk een nieuwe `load()`-aanroep. Voor wisselen zonder
paginaverversing gebruikt de app daarom de in deze versie aanwezige
`__internal_updateProps`-functie, met het volledige taalobject. Bij een toekomstige
SDK-upgrade moet deze integratie opnieuw worden gecontroleerd. Dit is geverifieerd
in het opgehaalde vastgezette script en de
[officiële broncode](https://github.com/clerk/javascript/blob/main/packages/clerk-js/src/core/clerk.ts);
de taalobjecten volgen de [Clerk-documentatie](https://clerk.com/docs/guides/customizing-clerk/localization).

Er is geen belastingtest voor grote aantallen gelijktijdige gebruikers. Lijsten
en historie gebruiken paginering; gedeelde updates worden gepolld en verschijnen
doorgaans binnen 15 seconden op een zichtbaar scherm. Bestaande reserveringsregels,
inclusief externe inkorting versus opnieuw aanvragen, blijven gelden.

## Bestanden voor deze release

Website: `index.html` en `han-logo.svg`. Database:
`SQL/migrations/20260929192403_connectr_profiles_conversations.sql` en de
bijgewerkte `SQL/verify.sql`. Documentatie: `README.md`, `SQL/README.md`,
`SQL/migrations/README.md` en dit opleveringsverslag. Testinrichting: `package.json`,
`tests/browser.mjs`, `tests/db-harness.mjs`, `tests/frontend.mjs`,
`tests/setup-browser.mjs`, `tests/connectr.mjs`, `tests/validation.mjs` en
`tests/translation-audit.mjs`. Geen nieuwe productiedependencies.

SHA-256 van de voorbereide productiebestanden (1 oktober 2026):

| Bestand | SHA-256 |
| --- | --- |
| `index.html` | `d184a6865f79930ae45e6c80b77b7ae32db2d94fd812ee457224e379f8db9ae0` |
| `han-logo.svg` | `efb199beaaa08a0cb7635a21feb426060f5d46c1a56c1d40a5a337abdcd8284b` |
| Connectr-migratie | `0df766f7aabc731032985238c0144a46804f4ecad008cd34755ec2460a62b567` |

## Exacte publicatievolgorde na eindgoedkeuring

1. Controleer opnieuw de actuele `main` en live migraties. Gebruik een checkout
   van de actuele publicatie; deze lokale herstelmap heeft ook oudere staged
   bestanden. Commit uitsluitend de voorbereide wijzigingen, geen lokale sleutels,
   testdatabases of screenshots.
2. Leg aantallen vast en maak een beveiligde herstelkopie van de huidige relevante
   tabellen/schema's vóór uitvoering. Bewaar persoonlijke gegevens buiten GitHub.
3. Publiceer tijdelijk de bestaande onderhoudspagina via `main` en controleer de
   Vercel-uitrol. Dit is een korte onderhoudsonderbreking. Reeds geopende oude
   pagina's blijven door databasecontroles begrensd.
4. Zet in de bestaande Clerk-app voor- en achternaam verplicht voor registratie.
   Gebruik de bestaande configuratie; geen nieuwe Clerk-app of domeinmigratie.
5. Pas uitsluitend de genoemde Connectr-migratie toe via Supabase `apply_migration`,
   met naam `connectr_profiles_conversations`. **Geen reset, basis of startgegevens
   opnieuw uitvoeren.** De migratie is transactioneel en eenmalig.
6. Controleer migratieregistratie, tabelrechten, functiegrants, behoud van aantallen
   en gemigreerde historie met de alleen-lezen controles in `SQL/verify.sql`.
7. Push de definitieve `index.html`, `han-logo.svg`, deze migratie, bijbehorende
   testwijzigingen en documentatie naar `LodiWigman/ruimte-reserveren/main`.
   Vercel publiceert automatisch. Verifieer opgehaalde bestanden en de uitrol.
8. Controleer met echte ingelogde accounts profiel/registratie, reserveren, gesprek,
   belletje en NL/EN. Wanneer daarvoor geen ingelogde sessie beschikbaar is,
   rapporteer precies welke laatste praktijktest nog nodig is.

Bij een mislukte migratie blijft de transactie zonder gedeeltelijke wijziging.
Zet dan de bestaande publicatie terug na verificatie. Na een geslaagde migratie
mag de oude frontend niet los worden teruggezet: laat onderhoud actief en herstel
gericht, met behoud van intussen ontvangen gegevens. Geen automatische reset.

De eindgoedkeuring omvat de voorbereide website, één gerichte databasemigratie,
de bijbehorende Clerk-naaminstellingen en de korte onderhoudspublicatie. De
goedkeuring voor eerdere releases geldt niet voor deze release.
