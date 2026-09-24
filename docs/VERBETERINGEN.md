# Verbeteringen na praktijktest — voorbereid op 24 september 2026

Het werkplan en de afgeronde release zijn expliciet goedgekeurd, inclusief opnieuw
goedkeuren van externe reserveringen bij een andere datum of ruimte.
GitHub-bron vóór publicatie: `89cd6e3` op `main`.
De databasewijziging is op 24 september 2026 toegepast als
`20260924091138_reservation_workflows`; het geteste bronbestand blijft
`SQL/migrations/20260922151039_reservation_workflows.sql`.

De live nacontrole bevestigt: zes reserveringen behouden, metadata overgenomen,
zes goedgekeurde verzoeken verwijderd, profielen/adminrol, 18 ruimtes en overige
gegevens behouden. RLS staat op alle zes tabellen; directe schrijftoegang en
anonieme toegang zijn ingetrokken. De overlapconstraint blijft actief.
De 15 security-advisorwaarschuwingen betreffen bewust toegankelijke, gecontroleerde
SECURITY DEFINER-functies. Vijf performance-informaties betreffen drie ontbrekende
indexen op behandelaren en twee nog ongebruikte indexen; geen directe actie nodig
bij de huidige omvang. Zie de actuele toelichting in VERIFICATIE.md.

## Opgeleverd in de voorbereide versie

- Verplichte velden hebben een sterretje en de uitleg `* = verplicht`.
  Organisatie/afdeling en gelegenheid blijven verplicht voor externen;
  motivatie/toelichting en omschrijving zijn optioneel. Intern/admin kan eveneens
  organisatie/afdeling invullen, optioneel.
- Vrije beschikbaarheid staat als subtiele roze toelichting. Conflicten en mislukte
  controles blijven herkenbare waarschuwingen.
- Alle algemene meldingen blijven vijf seconden vast bovenin het scherm, ook na
  scrollen en in het wijzigingsvenster. Nieuwe meldingen krijgen hun eigen vijf seconden.
- Succesvolle inzending/wijziging verwijst naar controle in het overzicht.
- ‘Herhalen tot en met’ neemt de einddag mee wanneer die binnen het gekozen patroon valt.
- Eigen tab ‘Intern/admin rol aanvraag’. Externen vragen intern/admin aan; internen
  alleen admin. De huidige rol verandert pas na goedkeuring door een bestaande admin.
- ‘Mijn verzoeken/reserveringen’ toont ook rolverzoeken, met wijzigen/intrekken
  voor de eigen open aanvragen.
- Reeksen zijn uitklapbaar in het persoonlijke overzicht, bij beheerdersverzoeken
  en onder alle reserveringen. De losse momenten blijven individueel bedienbaar.
- Goedgekeurde verzoeken verdwijnen na het aanmaken van de reservering, in dezelfde
  transactie. Organisatie/afdeling, gelegenheid en motivatie gaan mee naar de reservering.
- Externen wijzigen eigen reserveringen. Inkorten blijft bevestigd; eerder beginnen,
  later eindigen of een andere datum/ruimte wordt opnieuw een verzoek. De geselecteerde
  oude reservering vervalt dan. Dit staat op het formulier en in de bevestigingsvraag.
- Admins kunnen alle reserveringen en open verzoeken wijzigen. Ook bij beheer blijft
  de eigenaar behouden en kan geen bevestigde overlap ontstaan.
- Het ruimteoverzicht toont ‘Mijn reservatie’/‘Mijn verzoek’. Naam en organisatie/afdeling
  van bevestigde reserveringen zijn zichtbaar voor ingelogde gebruikers bij aanwijzen
  of klikken. Overige privégegevens blijven afgeschermd.
- Klikken op een eigen aankomend item, of als admin op een aankomend item, opent
  het bestaande wijzigingsformulier in een venster binnen de website. Andere/historische
  items openen alleen beperkte details. De ruimtecode is groter weergegeven.

## Gevolgen voor bestaande gegevens

Geen reset. Profielen, adminrol, ruimtes, reserveringen, open/afgewezen verzoeken,
rolverzoeken en support blijven behouden. De migratie voegt drie metadatavelden aan
reserveringen en de gewenste rol aan rolverzoeken toe. Oude rolverzoeken blijven
aanvragen voor intern, zoals oorspronkelijk bedoeld.

Goedgekeurde reserveringsverzoeken worden verwijderd, inclusief hun behandelnotities
en afzonderlijke verzoekhistorie. De bevestigde reserveringen blijven bestaan.
Organisatie/afdeling, gelegenheid en motivatie worden eerst overgenomen bij een
eenduidige koppeling op eigenaar, ruimte, datum, tijden en reeks. Bij de live hercontrole
waren er zes reserveringen en zes goedgekeurde verzoeken, alle zes eenduidig gekoppeld.
Bij afwijkingen vlak vóór uitvoering worden de gevolgen opnieuw beoordeeld.

Er worden geen ontbrekende organisaties verzonnen. Een onbekende waarde verschijnt
als ‘Niet opgegeven’. Importbestanden zonder organisatiegegevens blijven ondersteund.

## Controles en grenzen

Zie [VERIFICATIE.md](VERIFICATIE.md) voor uitgevoerde scenario's. De tests gebruiken
PostgreSQL 17.6 en echte HTML/Supabase SDK/SheetJS met nagebootste Clerk-sessies.
Echte Clerk-tokenvalidatie en de gehoste website vereisen de eigen-logincontrole na
publicatie. Clerk blijft development; deze wijziging schakelt niet naar productie.
Geen volledige belastingtest, pentest of toegankelijkheidsaudit.

## Uitvoering na laatste goedkeuring

1. Controleer `main`, live functies, kolommen, actuele rollen en aantallen opnieuw.
   Bewaar verse applicatiegegevens en definities lokaal buiten de repository.
2. Pas uitsluitend `SQL/migrations/20260922151039_reservation_workflows.sql` toe via
   de Supabase-migratieconnector. De complete migratie zit in één atomair DO-statement.
   Gebruik niet de oude reset of `basis.sql` op de bestaande database.
3. Controleer nieuwe velden, functies, effectieve rechten, behouden reserveringen,
   overgenomen metadata, opgeruimde goedgekeurde verzoeken en migratiehistorie/advisors.
4. Publiceer deze `index.html`, SQL, tests en documentatie samen naar GitHub `main`.
   De database gaat eerst: de oude website kan de nieuwe contracten nog aanroepen,
   maar toont tot de codeverversing niet alle nieuwe mogelijkheden.
5. Vergelijk de GitHub-bestanden met de geteste versie. Vercel neemt `main` automatisch
   over; op verzoek van de gebruiker wordt Vercel niet afzonderlijk gecontroleerd.

Een fout tijdens de migratie draait de hele wijziging terug; dit is lokaal getest.
Na een geslaagde migratie niet opnieuw uitvoeren of resetten. Bij problemen eerst
onderzoeken en een gerichte herstelmigratie maken. Herstel verwijderde verzoekhistorie
alleen uit de vooraf bewaarde gegevenskopie als dat daadwerkelijk nodig is.

## Eigen praktijktest na publicatie

1. Ververs de website volledig en test als extern de sterretjes en een leeg verplicht
   veld. De melding moet zonder scrollen zichtbaar zijn en na vijf seconden verdwijnen.
2. Dien een verzoek in zonder motivatie. Maak ook drie herhalingen tot en met de laatste
   dag. Controleer het uitklapbare reeksblok en het label ‘Mijn verzoek’.
3. Keur als admin de reeks goed. Controleer dat alleen reserveringen overblijven en
   dat naam/organisatie zichtbaar zijn in het overzicht.
4. Klik als extern op de eigen reservering: kort in en controleer dat zij bevestigd
   blijft. Verleng of verplaats en controleer dat er opnieuw een verzoek ontstaat.
5. Vraag een rol aan, wijzig het open verzoek en trek het in. Test goedkeuring met
   een bewust gekozen testaccount; een adminrol geeft daadwerkelijke beheerrechten.
6. Test als admin wijzigen vanuit het overzicht en herhaal de belangrijkste handelingen
   op mobiel. Controleer ook ‘alleen deze’ versus ‘deze en volgende’.
