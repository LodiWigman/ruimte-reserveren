# HAN@Connectr — versie voor eindgoedkeuring

**1 oktober 2026. Voorbereid; nog niet gepubliceerd.** De opdrachtgever heeft
expliciet bevestigd dat
de bestaande Clerk-testomgeving voorlopig blijft gebruikt. Geen verplichte MFA.
Er wordt geen volledige platformcertificering geclaimd.
Dit overzicht vervangt de eerdere publicatieblokkade en verouderde releasehashes.

## Inhoud van de release

- HAN@Connectr-interface en NL/EN, verplichte profielnaam, boeken namens accounts
  of gasten en gecontroleerde overdracht van reserveringen/verzoeken.
- Doorlopende gesprekken voor vragen, klachten en tips, anonimiteit tegenover
  appbeheerders, archief, meldingen, persoonlijke gelezenstatus en gezamenlijk beheer.
- Verbeterde privacy, rechtencontrole, conflictbehandeling, sessie-intrekking,
  schrijfquota, auditregistratie, foutmeldingen en veilige importverwerking.
- CSP, integriteitscontroles en hostingheaders. De publicatie-uitvoer bevat alleen
  `index.html` en `han-logo.svg`; SQL, tests en documentatie worden niet gehost.
- De build controleert de actuele script-hash, integriteit, headers en toegestane
  publicatiebestanden. Clerk development wordt ondersteund.

De naamcontrole in de applicatie en database blijft leidend: zonder bevestigde
voor- en achternaam kunnen gebruikers niet reserveren of verzoeken indienen.
De bestaande Clerk-account-ID's, rollen en gegevenskoppelingen blijven behouden.

## Efficiënt uitgevoerde controles

De applicatie- en migratiebestanden zijn ongewijzigd sinds de geslaagde volledige
hertest op 1 oktober. Die testuitkomsten worden hergebruikt na hashvergelijking:
71 functionele/databasecontroles, 24 beveiligingscontroles naast één oude
uitgangsbevinding, desktop/mobiel, formuliervalidatie, XSS/CSP en 15 importcontroles.
Er zijn in deze voorbereidingsronde geen nieuwe functionele wijzigingen aangebracht.

Aanvullend zijn de gewijzigde publicatiebuild en de echte openbare Clerk-interface
gericht getest. De Nederlandse aanmeld- en Engelse registratievensters laden met
de nieuwe CSP zonder browserfouten, geblokkeerde beleidsverzoeken of mislukte
netwerkverzoeken. Er zijn geen accounts aangemaakt en geen aanmeldgegevens ingevoerd.
De bouwtest bevestigt dat gewijzigde scriptinhoud, onjuiste bibliotheekintegriteit
en onverwachte privébestanden in de uitvoermap de build stoppen.

Read-only hercontrole op de gekoppelde diensten:

- GitHub `LodiWigman/ruimte-reserveren/main` staat nog op
  `75ab09f61c4dd534550db8380603d70b12e91804`; geen onverwachte nieuwe versie.
- Supabase `oappvdfjyvbmvqrjvnmv` eindigt nog op migratie
  `20260924091138 reservation_workflows`; de nieuwe migratie staat nog niet live.
- Alle zes openbare applicatietabellen hebben RLS; anonieme leesrechten en directe
  schrijfrechten voor aangemelde browseraccounts ontbreken.
- De advisor meldt alleen de bestaande 15 waarschuwingen over bewust uitvoerbare
  `SECURITY DEFINER`-API's. Hun rol-/eigenaarschapscontroles zijn lokaal getest;
  rechten zijn niet verruimd. [Uitleg van de advisor](https://supabase.com/docs/guides/database/database-linter?lint=0029_authenticated_security_definer_function_executable).
- Huidige uitgangsaantallen: 2 profielen, 1 beheerder, 7 bevestigde reserveringen,
  0 reserveringsverzoeken en 2 oude ondersteuningsmeldingen. Opnieuw vastleggen
  vlak vóór de migratie, omdat normaal gebruik deze aantallen kan veranderen.

Bewijs en de definitieve bestandsvingerafdrukken worden vastgelegd in
`docs/security/RELEASE-VERIFICATIE-2026-10-01.json`.

## Publicatie na jouw toestemming

Bestemming: **https://ruimte-reserveren.vercel.app/** via
**LodiWigman/ruimte-reserveren, branch main**, met één bijbehorende Supabase-migratie.

1. Controleer opnieuw de actuele GitHub-versie en migraties. Gebruik een schone
   checkout van de actuele `main`; deze werkmap bevat ook oudere staged bestanden.
   Neem uitsluitend de in het releasebewijs genoemde bestanden mee.
2. Zet de bestaande onderhoudspagina tijdelijk online en controleer de uitrol.
   Als de nieuwe buildconfiguratie dan nog niet is toegevoegd, gebruik de bestaande
   publicatiemethode. Een onderhoudspagina mag niet met de CSP van de definitieve
   applicatie worden verpakt. Zo blijven frontend en database tijdens de overgang consistent.
3. Maak vóór databasewijzigingen een afgeschermde herstelkopie van schema en
   betrokken tabellen, controleer dat de kopie leesbaar is en leg aantallen vast.
   Bewaar persoonsgegevens en herstelgegevens buiten GitHub en de publieke uitvoer.
   Zonder geslaagde herstelkopie niet doorgaan met de migratie.
4. Zet in de bestaande Clerk-app voor- en achternaam verplicht bij registratie,
   zoals in de oorspronkelijke oplevering voorzien. Geen nieuwe Clerk-app, MFA,
   productieovergang of gewijzigde account-ID's. De app en database controleren
   de namen daarnaast zelfstandig. Deze dashboardinstelling is nog niet gewijzigd.
5. Pas uitsluitend
   `SQL/migrations/20260929192403_connectr_profiles_conversations.sql` toe via
   Supabase, onder de naam `connectr_profiles_conversations`. Geen reset, basis,
   startgegevens of oude migraties opnieuw uitvoeren. Deze migratie is transactioneel.
6. Controleer migratieregistratie, behoud van bestaande gegevens, rechten en
   gemigreerde gesprekshistorie met `SQL/verify.sql`.
7. Publiceer de goedgekeurde website, het logo en `vercel.json` met de bijbehorende
   bouwbestanden. Vercel bouwt de afgeschermde uitvoermap `dist` automatisch.
8. Controleer de live pagina, headers en onbereikbaarheid van SQL/testbestanden.
   Controleer vervolgens met een echte aangemelde sessie profiel, reservering,
   gesprek, meldingen en afmelden. Als daarvoor geen sessie beschikbaar is,
   meld die resterende praktijktest expliciet; doe niet alsof zij is uitgevoerd.

Bij een mislukte migratie rolt de transactie terug; herstel na verificatie de oude
website. Na een geslaagde migratie niet zomaar de oude frontend terugzetten:
houd onderhoud actief en herstel gericht, met behoud van gegevens. De lokale test
heeft zowel migratiebehoud als terugdraaien bij een fout geverifieerd.

## Resterende grenzen en beheerpunten

De echte openbare Clerk-vensters zijn getest; een volledige aanmelding en de
bijbehorende tokenverificatie door Supabase zijn nog niet end-to-end bewezen.
Daarvoor is na de goedgekeurde uitrol een echte gebruikerssessie nodig.

Het platform draait op PostgreSQL 17.6. Het eerder gesignaleerde leveranciersonderhoud
blijft een apart beheeractiepunt, evenals bewaartermijnen, bewaking en een volledige
back-upherstelproef. Er is geen database-upgrade, nieuwe betaalde testomgeving of
grootschalige belastingtest onderdeel van deze release. De voorafgaande herstelkopie
uit stap 3 blijft wel verplicht. Een afzonderlijke online testomgeving wordt niet aangemaakt.

**De eindgoedkeuring omvat:** de voorbereide website en hostingconfiguratie,
één gerichte databasemigratie, de Clerk-naaminstellingen en een korte onderhoudsperiode.
Er wordt pas gepusht of live gewijzigd nadat de opdrachtgever dit overzicht goedkeurt.
