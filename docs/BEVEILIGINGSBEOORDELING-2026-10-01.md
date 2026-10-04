# Beveiligingsbeoordeling HAN@Connectr

**Historische beoordeling vóór de beveiligingsaanscherping.** Dit document blijft
bewaard als oorspronkelijke bevindingenlijst. De wijzigingen, hertest en resterende
voorwaarden staan in [het actuele publicatieoverzicht](PUBLICATIEKLAAR-2026-10-01.md).
Hashwaarden en bevindingen hieronder beschrijven de destijds beoordeelde versie.

**Peildatum: 1 oktober 2026. Advies: nog niet vrijgeven voor brede productie namens HAN.**

De lokale versie bevat aantoonbare toegangsbeveiliging en doorstaat gerichte aanvalstests,
maar er zijn concrete privacytekortkomingen en belangrijke controles ontbreken nog.
De eerdere aanduiding “klaar voor oplevering” beschreef de functionele voortgang te ruim:
de geslaagde functionele tests rechtvaardigen geen oordeel dat het hele systeem
voldoende veilig is voor productie bij een publieke organisatie.

Er is geen bewijs gevonden van een daadwerkelijke inbraak. Deze beoordeling is geen
onderzoek naar historische incidenten en kan dus ook niet uitsluiten dat die hebben
plaatsgevonden. Het is een zelfbeoordeling door dezelfde ontwikkelassistent, geen
onafhankelijke penetratietest of beveiligingscertificering.

## Onderzochte versie en methode

Onderzocht zijn de bestaande databasebeveiliging, de lokale voorbereide release,
de openbare configuratie van de gebruikte Clerk-aanmelding en de publiek bereikbare
GitHub Pages-website. De live database is uitsluitend met leesopdrachten onderzocht;
de aanvalsscenario's gebruikten een tijdelijke lokale PostgreSQL-database met fictieve
personen. De browserproeven gebruikten de lokale website met nagebootste aanmelding.
Er zijn geen echte gebruikers aangevallen, geen wachtwoorden geprobeerd en geen
belastingaanvallen op live diensten uitgevoerd.

GitHub: `LodiWigman/ruimte-reserveren`, `main`, gecontroleerde remote commit
`75ab09f61c4dd534550db8380603d70b12e91804`.
Supabase: `oappvdfjyvbmvqrjvnmv`; live migratiehistorie eindigt op
`20260924091138 reservation_workflows`. De nieuwe profiel-/gespreksmigratie is
**alleen lokaal aanwezig**. De huidige live versie en de voorbereide versie zijn
daarom niet even veilig en worden hieronder apart benoemd.

De applicatiebestanden zijn tijdens deze beoordeling niet gewijzigd. SHA-256:

| Bestand | Hash |
|---|---|
| `index.html` | `D184A6865F79930AE45E6C80B77B7AE32DB2D94FD812EE457224E379F8DB9AE0` |
| `han-logo.svg` | `EFB199BEAAA08A0CB7635A21FEB426060F5D46C1A56C1D40A5A337ABDCD8284B` |
| `SQL/migrations/20260929192403_connectr_profiles_conversations.sql` | `0DF766F7AABC731032985238C0144A46804F4ECAD008CD34755EC2460A62B567` |

## Bevindingen die eerst aandacht vragen

De prioriteiten hieronder zijn een praktische inschatting voor deze toepassing;
het zijn geen formeel berekende CVSS-scores.

### B01 — Hoog: ontwikkelaanmelding en geen tweede factor

**Bevestigd voor de momenteel geconfigureerde Clerk-omgeving.** De website verwijst
naar een `pk_test_`-sleutel. De openbare omgevingsconfiguratie meldt `development`,
`test_mode: true`, een lege lijst `second_factors` en geen verplichte tweede factor.
Zelfregistratie staat op `public`; een allowlist staat uit. Dit betreft de
applicatieaanmelding, niet de apart te controleren accounts van GitHub, Supabase en
Vercel-beheerders.

Daarmee ontbreekt een belangrijke bescherming tegen overname van een appbeheeraccount.
Ontwikkelmodus is op zichzelf geen bewezen authenticatie-omzeiling, maar is geen
voldoende onderbouwde productieconfiguratie. Positief: de configuratie bevat wel
e-mailverificatie bij registratie, registratie-CAPTCHA, accountvergrendeling na
herhaalde pogingen en controle op bekende gelekte wachtwoorden. Bescherming tegen
het achterhalen of een account bestaat (`enumeration_protection`) staat uit; dit
is uit de configuratie afgeleid en niet met echte accounts beproefd.

**Voor vrijgave:** productieomgeving en domein inrichten, minimaal beheerders met
verplichte sterke tweede factor beveiligen, bepalen wie zich mag registreren en de
echte Clerk–Supabase-koppeling testen. Bij overstappen moeten bestaande account-ID's,
eigenaarschap en beheerrechten gecontroleerd behouden of gemigreerd worden.
Alleen een andere sleutel invullen is onvoldoende. Zie
[Clerks productiehandleiding](https://clerk.com/docs/guides/development/deployment/production).

### B02 — Hoog: namen en organisaties zichtbaar voor externe accounts

**Bevestigd in de bestaande functie en lokaal gereproduceerd in de nieuwe versie.**
`SQL/basis.sql`, functie `han_occupancy`, geeft bij bevestigde reserveringen naam en
organisatie terug aan iedere aangemelde gebruiker, ook met rol `extern`. Andere
reserveringsdetails en de boekings-ID worden voor onbevoegden wel afgeschermd.

De API begrenst één aanvraag tot 32 dagen, maar kent geen overeenkomstige grens
voor hoeveel perioden iemand achtereen opvraagt. Ook historische perioden zijn
opvraagbaar. Gecombineerd met openbare registratie maakt dit het verzamelen van
naam, organisatie, ruimte en tijdstippen mogelijk. Dit is bestaand functioneel gedrag;
het is geen aangetoonde omzeiling van databasebeveiliging. Het is wel een wezenlijk
risico door te brede gegevensverstrekking.

**Voor vrijgave:** laat de gegevensverantwoordelijke vaststellen wie deze gegevens
nodig heeft. Mijn voorstel is dat externen standaard alleen bezetting zien, met
persoonsgegevens uitsluitend voor eigenaar en bevoegde beheerders. De gekozen regel
moet in de API worden afgedwongen, inclusief historische gegevens; alleen de tekst
uit de interface verbergen helpt niet.

### B03 — Hoog bij beloofde anonimiteit: live supporttabel onthult afzender-ID

**Bestaande live situatie:** de tabelrechten en policies laten een appbeheerder
supportregels inclusief `user_id` lezen. Het lokaal nagebouwde bestaande schema
bevestigt dit. Met toegang tot profielen kan die ID aan een persoon gekoppeld worden.
Er zijn voor deze proef geen echte supportberichten opgevraagd.

**Voorbereide versie:** de nieuwe migratie verplaatst deze gegevens naar een private
tabel. De gecontroleerde gespreks-API's en beheerdersmeldingen laten bij anonieme
gesprekken geen afzender-ID, profielnaam of opgegeven e-mailadres door. Gerichte
tests bevestigen dit. Deze verbetering beschermt de huidige live omgeving nog niet.

“Anoniem” betekent ook in de nieuwe versie: anoniem tegenover functionele
appbeheerders. Technisch databasebeheer kan de koppeling nog zien en de gebruiker
kan zichzelf in vrije tekst herkenbaar maken. Die grens moet duidelijk worden
uitgelegd. De nieuwe migratie moet na de totale vrijgave gecontroleerd worden
uitgevoerd; deze bevinding is geen reden om nu ongecontroleerd te publiceren.

### B04 — Middel: ontbreken van aantoonbare browserbeveiligingsmaatregelen

De lokale HTML laadt scripts van externe leveranciers zonder `integrity`-controle
(SRI) en bevat geen Content Security Policy (CSP). Versies zijn wel vastgezet.
Een externe scriptleverancier blijft daarmee onderdeel van de vertrouwensketen.

De publiek bereikbare [GitHub Pages-versie](https://lodiwigman.github.io/ruimte-reserveren/)
gaf bij deze controle HTTP 200 en HSTS terug, maar geen CSP, `X-Frame-Options`,
`X-Content-Type-Options` of expliciete `Referrer-Policy`. De HTML bevatte ook geen CSP
of SRI. Zonder framebeperking ontbreekt een gebruikelijke maatregel tegen
misleidende bediening via een ingebedde pagina. Er is geen geslaagde clickjacking-
of scriptleveranciersaanval aangetoond.

Deze headerwaarneming geldt **alleen voor de gemeten GitHub Pages-URL**. Ze bewijst
niets over de Vercel-productieheaders: de daadwerkelijke Vercel-site is niet
geverifieerd. Eerdere projectdocumentatie hield die controle buiten scope.

**Voor vrijgave:** bepaal het officiële publicatieadres en wat met andere bereikbare
kopieën gebeurt; configureer passende browserheaders op dat adres, een werkende CSP
en gecontroleerde levering van scripts. Test daarbij Clerk, imports en de interface.
Een strenge CSP vraagt ook aanpassing van de huidige inline eventhandlers.

### B05 — Middel: geen toepassingsquotum tegen herhaald indienen

Een fictief extern account kon lokaal 25 kleine gesprekken achtereen aanmaken.
De databasefuncties hebben geen aangetoond quotum per account voor dit gebruik.
Groottevalidatie, batchlimieten en time-outs zijn wel aanwezig. Registratie-CAPTCHA
beperkt bovendien niet automatisch wat een reeds ingelogd account kan indienen.

Dit bewijst dat deze beperking op applicatieniveau ontbreekt, niet dat de live dienst
met 25 verzoeken overbelast raakt. Eventuele aanvullende providerlimieten zijn niet
geverifieerd. Mogelijke gevolgen zijn vervuiling van beheerwerk, gegevensgroei en
extra kosten.

**Voor vrijgave:** redelijke accountgebonden indienlimieten en misbruikdetectie
inrichten, met een herstelprocedure voor legitieme gebruikers. Capaciteit en gedrag
bij limieten gecontroleerd in een aparte testomgeving meten.

### B06 — Laag: latere status blijft zichtbaar na overdracht

**Nieuwe lokale versie:** `han_notifications` berekent `accessible` en
`current_status` afzonderlijk. De proef droeg een verzoek over en liet de nieuwe
eigenaar een latere afwijzing ontvangen. De vorige eigenaar zag via de oude
overdrachtsmelding toch `current_status: rejected`, terwijl `accessible: false` was.

Het verzoek zelf bleef ontoegankelijk; dit is een beperkt lek van actuele status,
geen volledige inzage. Het past niet bij het uitgangspunt dat persoonlijke toegang
na overdracht vervalt. **Voor vrijgave:** status alleen uit het actuele item ophalen
als de ontvanger nog toegang heeft; eventueel de historische melding zelfstandig
laten bestaan. Voeg daarna een gerichte regressietest toe.

## Wat aantoonbaar goed werkt

De eerdere verificatie omvatte 71 functionele/database-scenario's, een desktop- en
mobiele browserdoorloop en afzonderlijke veldvalidatieproeven. Dat waren geen 71
onafhankelijke beveiligingstests.

De aanvullende beveiligingssuite bevat **18 scenario's: 14 bevestigen bescherming,
4 bevestigen bestaande tekortkomingen/gedrag** (B02, B03, B05 en B06). Het succesvolle
afronden van die suite betekent dus nadrukkelijk niet dat alle bevindingen zijn
opgelost. De browserproef beproefde daarnaast vijf XSS-invoervarianten over
reserveringen, verzoeken, gesprekken, rolverzoeken en ruimten, inclusief inline
ruimtelinks en tooltips. Geen van deze varianten voerde code uit of maakte een
geïnjecteerd HTML-element aan.

Bevestigde bescherming in de gecontroleerde scenario's:

- Niet-ingelogde databasegebruikers kunnen applicatietabellen en afgeschermde API's
  niet lezen of aanroepen.
- Gewone gebruikers kunnen hun rol niet rechtstreeks verhogen. Zelf meegestuurde
  eigenaar, maker, rol en goedkeuringsstatus worden niet als gezaghebbend vertrouwd.
- Een geraden reserverings- of gespreks-ID geeft geen toegang tot andermans item,
  reacties, wijziging, annulering of overdracht.
- Private tabellen en schrijfhulpfuncties zijn ook voor appbeheerders niet
  rechtstreeks toegankelijk in de nieuwe versie.
- SQL-injectietekens in de onderzochte invoer bleven gegevens; tabellen en rollen
  bleven intact. De onderzochte HTML/JavaScript-invoer bleef onuitvoerbare tekst.
- Onjuiste versies en overdrachtsvingerafdrukken passeren de conflictcontrole niet.
  Te grote batches en ongeldige invoer worden geweigerd.
- De nieuwe anonieme gespreksweergaven schermen de technische afzendergegevens af.

Live cataloguscontrole bevestigde RLS op alle zes applicatietabellen, geen directe
schrijfrechten voor `anon` of `authenticated`, beperkte leespolicies en een vaste
lege `search_path` voor de gecontroleerde functies. De Supabase security advisor
meldde één waarschuwingscategorie voor 15 door aangemelde gebruikers uitvoerbare
`SECURITY DEFINER`-functies. Die constructie is hier bewust gebruikt om gecontroleerde
bewerkingen uit te voeren en vraagt dus controle van iedere functie; de waarschuwing
is niet automatisch bewijs van 15 lekken. Zie de
[uitleg van Supabase bij deze waarschuwing](https://supabase.com/docs/guides/database/database-linter?lint=0029_authenticated_security_definer_function_executable).

## Controle van externe bibliotheken

`pnpm audit --json` rapporteerde nul bekende kwetsbaarheden in 27 lokale
testafhankelijkheden. De productiepagina laadt bibliotheken via CDN: die zijn door
deze pakketcontrole niet automatisch afgedekt.

Een aanvullende OSV-versiecontrole gaf geen treffers voor Supabase JS 2.116.0,
Clerk JS 6.32.1, Clerk UI 1.33.1 en Clerk localizations 4.20.0. Voor `xlsx` 0.20.3
leverde de npm-gerelateerde index twee waarschuwingen. Handmatige toetsing aan de
adviezen van SheetJS bevestigt dat de gebruikte CDN-versie buiten de beschreven
kwetsbare reeksen valt: de patches zitten vanaf 0.19.3 respectievelijk 0.20.2.
Deze twee waarschuwingen worden daarom **niet als bevestigde kwetsbaarheid in de
gebruikte versie** gerapporteerd. Bronnen:
[CVE-2023-30533](https://cdn.sheetjs.com/advisories/CVE-2023-30533) en
[CVE-2024-22363](https://cdn.sheetjs.com/advisories/CVE-2024-22363).

Dit is een controle van bekende meldingen per opgegeven versie, geen volledige
analyse van alle meegebundelde componenten of de integriteit van geleverde scripts.

## Nog onvoldoende onderzocht

| Onderdeel | Ontbrekend bewijs vóór productie |
|---|---|
| Echte authenticatie | Correcte ondertekening en issuer/audiencecontrole van tokens; verlopen, vervalste en ingetrokken sessies; logout, wachtwoordherstel, MFA en accountwisseling met echte testaccounts. De lokale harness zet zelf testclaims en bewijst deze controles niet. |
| Hosting en sessies | Werkelijke productieheaders, toegestane domeinen/redirects, cookies, bescherming tegen CSRF en ongewenste framing in de gebruikte live opstelling. |
| Accountbeheer | Wie admin mag worden, periodieke controle, intrekken bij uitdiensttreding, herstel van een verloren beheeraccount en MFA van providerbeheeraccounts. |
| Traceerbaarheid | Overdrachtslog en gespreksgeschiedenis bestaan lokaal, maar geen aangetoond volledig en beschermd auditspoor voor alle beheeracties, gegevensinzage en verwijderingen, plus opvolging van alarmen. |
| Herstelbaarheid | Beschikbaarheid, toegang en bewaartermijn van beheerde back-ups; een daadwerkelijk uitgevoerde herstelproef met afgesproken hersteltijden. Migratierollbacktests zijn daarvoor geen vervanging. |
| Gegevensbeheer | Welke persoonsgegevens en mogelijk gevoelige klachten worden opgeslagen; bewaartermijnen, verwijdering, export, toegang tot back-ups en verantwoordelijkheid binnen HAN. |
| Dienstbeheer | Organisatorisch eigenaarschap van repository, domein en cloudaccounts; leveranciersafspraken, gegevenslocatie, configuratie van opslagversleuteling en incidentprocedure. Dit is niet als ontbrekend bewezen, maar nog niet vastgesteld. |
| Overige aanvalsvlakken | Volledige dependency-/geheimenscan inclusief repositoryhistorie, schadelijke importbestanden, browserfuzzing, belasting en providerconfiguratie zijn niet volledig onderzocht. |

De openbare Supabase-anonsleutel en Clerk-publishable key zijn bedoeld voor
browsergebruik. Hun zichtbaarheid is op zichzelf geen gelekt beheerwachtwoord.
De beoordeling mag echter niet worden gelezen als bewijs dat nergens in het project
of de geschiedenis een geheim is achtergebleven.

## Voorgestelde volgorde na een nieuwe opdracht

1. Eerst de gewenste gegevensinzage en registratiegrenzen vastleggen en B02/B06
   lokaal herstellen. De nieuwe anonimiteitsbescherming behouden en expliciet testen.
2. Productieaanmelding, beheer-MFA, hostingheaders en toepassingslimieten voorbereiden.
   Bij een andere Clerk-omgeving een behoudend migratieplan voor accountkoppelingen
   maken. Geen live omschakeling zonder een concreet beoordeelbare versie.
3. In een aparte testomgeving de echte authenticatieketen, rechten, sessie-intrekking,
   imports en misbruiklimieten testen; herstel van een back-up demonstreren.
4. HAN-verantwoordelijken laten beslissen over gegevensgebruik, beheer en resterende
   risico's. Een onafhankelijke beveiligingsreview/pentest laten uitvoeren met een
   afgesproken scope en een passend toetsingskader. Een volledige onafhankelijke
   beveiligingsbeoordeling is niet uitgevoerd.
5. Pas daarna een nieuw overzicht met resultaten en open punten ter
   publicatiegoedkeuring voorleggen.

Voor bestaand live gebruik verdienen B01–B03 nu al prioriteit. Publicatie van nieuwe
functionaliteit uitstellen vermindert die bestaande blootstelling niet vanzelf.
Er zijn in deze beoordeling geen instellingen aangepast of gegevens verwijderd.

## Herleidbaar bewijs

Nieuwe lokale tests: `tests/security-assessment.mjs` en `tests/security-browser.mjs`.
Beide eindigden met exitcode 0, met bovengenoemd onderscheid tussen bescherming en
bevestigde bevindingen. Herhalen vanuit de release-map:

```powershell
node tests/security-assessment.mjs
$env:TEST_BROWSER_CHANNEL='msedge'
node tests/security-browser.mjs
```

De eerste test start uitsluitend een tijdelijke lokale database. Databaseproeven
mogen niet parallel worden gestart omdat de harness een vaste lokale poort gebruikt.
De tweede test vereist de reeds voorbereide lokale browsercache.

Lokaal bewaard, uitgesloten van Git: `test-results/security-assessment.json`,
`test-results/security-browser.json`, `test-results/clerk-public-environment.json`,
`test-results/public-host-security.json` en `test-results/browser-dependency-osv.json`.
Het auditresultaat voor de lokale pakketten staat in de uitvoer van deze sessie.

**Besluit van deze beoordeling:** behoud de publicatiepauze. De lokale basis is
verbeterd en meerdere aanvallen zijn tegengehouden, maar een positief productieadvies
is op dit moment niet verantwoord onderbouwd.
