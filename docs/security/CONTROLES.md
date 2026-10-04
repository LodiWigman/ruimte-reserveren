# Beveiligingsafspraken en toetsgrenzen

De opdrachtgever heeft Clerk development geaccepteerd. De technische maatregelen
hieronder blijven behouden, zonder verplichte MFA voor gebruikers. Het actieve
vrijgaveproces staat in [het publicatieoverzicht](../PUBLICATIEKLAAR-2026-10-01.md).
Het officiële adres is `https://ruimte-reserveren.vercel.app/`. De controles zijn
projectspecifiek en vormen geen onafhankelijke certificering.

## Gegevensstromen en toegang

De browser laadt de vaste HTML, het officiële logo en vastgezette bibliotheken.
Clerk verzorgt registratie, wachtwoorden en sessietokens. Supabase controleert het
token aan de API-grens. De database controleert account, sessie-ID, uitgever,
toegestane website, actuele rol en eigenaarschap. Een gebruikersrol uit zelf
meegestuurde metadata wordt genegeerd.

| Wie | Toegang en beperkingen |
|---|---|
| Niet aangemeld | Alleen de openbare website; geen applicatiegegevens of schrijf-API's. |
| Extern | Actieve ruimten en bezetting; eigen profiel, verzoeken, reserveringen, rolverzoeken, gesprekken en meldingen. Geen naam/organisatie/ID van andermans bezetting. Externe boekingen behoeven goedkeuring; inkorten van eigen bevestigde boeking volgt de bestaande regels. |
| Intern | Zelfde begrenzing van persoonsgegevens; mag vrije tijden direct reserveren. Geen inzicht in andermans privégesprekken. |
| Appbeheerder | Gedeeld functioneel beheer, boekingen namens iemand, overdracht, rollen en gesprekken. Geen eigen rol- of reserveringsverzoek goedkeuren. Geen afzenderidentiteit van als anoniem ingediende gesprekken, geen directe toegang tot private tabellen of beveiligingslog. |
| Technisch databasebeheer | Vertrouwde onderhoudsrol. Kan technisch bij de onderliggende identiteit; anonimiteit is tegenover functionele appbeheerders. Deze beheeraccounts en hun toegangsbeheer moeten apart worden gecontroleerd. |

Een gastboeking blijft eigendom van de verantwoordelijke beheerder. Na overdracht
vervallen de oude persoonlijke rechten, inclusief het opvragen van latere status
via een oude melding. Bevestigde en aangevraagde bezetting tonen alleen aan eigenaar
en beheerders naam/organisatie. Dezelfde regel geldt voor historische dagen.
Gesprekken, contactadressen en vrije tekst zijn vertrouwelijk; anonieme gegevens
worden expliciet uit beheerdersprojecties weggelaten. Het systeem verstuurt geen
e-mail en heeft geen openbare bestandsupload, GraphQL-interface, WebSocketfunctie,
OAuth-autorisatieserver of OS-commandofunctie in de applicatie.

## Geldigheid en transacties

De gezaghebbende controles staan in PostgreSQL-functies en constraints, niet alleen
in formuliercode. IDs zijn UUID's of gecontroleerde Clerk-ID's. Rollen zijn uitsluitend
extern/intern/admin. Boekingstijden zijn hele minuten, begin vóór einde, geldige
Nederlandse lokale kloktijd, geen verstreken datum en uiterlijk 31 december 2100.
Een ruimte moet bestaan en actief zijn. Een bezettingsaanvraag omvat maximaal 32
dagen. Een mutatie-/importbatch bevat maximaal 520 momenten. Een uitsluitingsconstraint
voorkomt overlappende bevestigde boekingen; transacties en locks voorkomen halve
reeksen en dubbele verwerking. Versies en SHA-256-vingerafdrukken voorkomen dat een
verouderd scherm een nieuwere wijziging overschrijft.

Profielnaam: niet-lege voor- en achternaam, samen maximaal 120 tekens. Organisatie
en gelegenheid maximaal 120, omschrijving/motivatie maximaal 500 tekens. Externen
moeten organisatie en gelegenheid invullen. Personen zijn een positief geheel getal;
ruimtecapaciteit is een waarschuwing en geen harde reserveringsgrens. Het eerste
gespreksbericht bevat 5–1500 tekens; reacties 1–5000; contactadres maximaal 254 met
eenvoudige structuurcontrole. Anonieme inzending wist het contactadres aan serverzijde.
Nieuwe categorieën zijn question/complaint/tip; unclassified is ook beschikbaar voor
historisch/beheerd materiaal. Het archief staat geen reacties toe. Rollen, maker,
eigenaarschap en status zijn niet vrij toewijsbaar via JSON-invoer.

## Limieten en imports

Limieten gelden per account voor geslaagde schrijfbewerkingen, in een uur- en
dagvenster dat bij de eerste bewerking begint. Beide vensters worden atomair
bijgewerkt. Ook beheerders vallen eronder. Een afgewezen transactie telt niet mee
en laat geen gedeeltelijke boeking, melding of auditregel achter.

| Bewerking | Per uur | Per dag |
|---|---:|---:|
| Nieuw gesprek | 20 | 100 |
| Gespreksbericht, inclusief openingsbericht | 120 | 600 |
| Invoegen/wijzigen reserverings- of verzoekrij | 2080 | 10400 |
| Profiel wijzigen | 60 | 240 |
| Overige beheerrij invoegen/wijzigen | 240 | 1200 |

Rijquota tellen ook series, imports, goedkeuringen, overdrachten en door een
profielwijziging bijgewerkte toekomstige boekingen mee. Daardoor kan een omvangrijke
legitieme bulkactie een limiet raken; verhoog limieten alleen na capaciteitsbeoordeling.
Een venstergrens kan twee opeenvolgende toegestane hoeveelheden toelaten: dit is
geen strikt voortschrijdend quotum. Er is nog geen aangetoonde globale/IP-begrenzing
voor mislukte aanvragen, leesverkeer of verspreide aanvallen. Database-time-outs
en registratie-CAPTCHA vervangen die maatregel niet.

Importbestanden worden alleen in de browser gelezen; de server ontvangt gevalideerde
boekingsrijen. Toegestaan: CSV, ICS, XLSX en OLE XLS; maximaal 5 MiB. Tekst met NUL en
ICS zonder kalenderopening worden geweigerd. XLSX moet een valide ZIP-container met
maximaal 256 entries en maximaal 20 MiB daadwerkelijk uitgepakte inhoud zijn.
Versleutelde/ZIP64/meer-schijfsarchieven, dubbele of afwijkende paden en VBA-materiaal
worden geweigerd. De uitgepakte hoeveelheid wordt tijdens decompressie gecontroleerd,
niet alleen op basis van een door het bestand opgegeven grootte.
XML-onderdelen worden vóór de spreadsheetparser gecontroleerd. DTD's en
entity-declaraties worden geweigerd, ook in UTF-16 met bytevolgordemarkering;
ongeldige tekencodering of NUL in gedecodeerde XML wordt afgewezen. Externe
XML-entiteiten zijn niet nodig voor het importeren van reserveringen.

De spreadsheetparser draait met geverifieerde bibliotheekbytes in een afzonderlijke
worker, maximaal 10 seconden, één werkblad, maximaal 520 gegevensregels en 32 kolommen.
Het bestand wordt niet gepubliceerd of op de server uitgevoerd. De controles zijn
geen antivirusverklaring; veelsoortige parserfuzzing blijft aanvullend werk.

## Browser, fouten en sessies

Inline JavaScript-handlers zijn vervangen door een expliciete actielijst met strikt
geparseerde letterlijke argumenten. Er wordt geen gebruikersinvoer met eval/Function
uitgevoerd. De CSP staat alleen de vaste scriptbronnen en de hash van de applicatie
toe, blokkeert script-attributen, objecten, base-URL-wijzigingen en inbedden. Inline
stijl blijft nodig voor de interface en Clerk. Twee hoofdlibs hebben SRI-controle;
Clerk en localeimports blijven aanvullende vertrouwde leveranciers. Bestanden voor
test-SDK's zijn ook tegen een vastgelegde integriteitslijst gecontroleerd.

Vercel krijgt HSTS, CSP, nosniff, no-referrer, framebeperking, beperkte apparaatfuncties
en no-store. Dit is lokaal getest/voorbereid; het is nog niet actief op productie.
De publicatie-uitvoer wordt beperkt tot index.html en han-logo.svg. SQL, tests,
documentatie, back-ups en versiebeheerbestanden komen niet in die uitvoermap.

Bekende domeinfouten worden begrijpelijk getoond; onbekende databasefouten tonen
geen query, sleutel of interne fouttekst. Bij afmelden verdwijnen ook verborgen
persoonlijke schermgegevens en conceptvelden. De app trekt de huidige sessie in
de database in en meldt daarna af bij Clerk. Bij verbindingsfalen wordt expliciet
gemeld dat afmelden niet volledig bevestigd is. Tests simuleren uitval en voorkomen
dat een later ontvangen antwoord van een vorig account weer gegevens toont.

`han_end_session` trekt uitsluitend de eigen ondertekende sessie in; nieuwe sessies
blijven onafhankelijk. `han_block_account` kan alleen door een andere beheerder
worden aangeroepen en blokkeert alle sessies van het doelaccount. Ontgrendeling is
bewust technisch onderhoud. Deze aanvullende maatregelen verifiëren geen
JWT-handtekening: dat blijft de taak van de Supabase/Clerk-integratie. Echte
registratie, herstel, tokenduur, providerlogout, uitdiensttreding/Clerk-verwijdering
en synchronisatie daarvan moeten nog met echte testaccounts worden gecontroleerd.

## Beheer dat nog moet worden bevestigd

De huidige Clerk-omgeving staat in development. Uit de openbare configuratie blijken
registratie-CAPTCHA, e-mailverificatie, blokkade na 100 mislukte pogingen gedurende
60 minuten en controle op bekende gelekte wachtwoorden. Dat is nog geen afgetekende
productie-inrichting. Vóór vrijgave zijn een aantoonbaar geschikte productie-inrichting,
een echte wachtwoordtest (minimaal 8 tekens; 15 aanbevolen zonder MFA), hersteltests
en verificatie van de bescherming tegen credential stuffing en ongewenste lockouts
nodig. Er wordt op verzoek geen verplichte MFA toegevoegd; providerbeheeraccounts
vallen onder apart organisatorisch beheer.

De nieuwe auditlog bevat tijd, actor, operatie, object en beperkte status/rol/eigenaars-
velden. Geen wachtwoorden, tokens, e-mail, namen of berichtinhoud. Appaccounts hebben
geen lees- of schrijfrechten op dit log. Technisch beheer blijft een vertrouwde grens.
Geweigerde API-pogingen en providerlogins zijn niet in dit transactielog vastgelegd;
daarvoor zijn gecontroleerde providerlogs/alarmering nodig. Bewaartermijnen, externe
logopslag en incidentopvolging zijn nog niet vastgesteld. Er is geen automatische
verwijdering van bestaande gegevens toegevoegd. Back-upbescherming en een echte
herstelproef blijven voorwaarden voor productie.

Voorgesteld onderhoudsbeleid voor componenten: bekende kritieke kwetsbaarheid direct
beoordelen en binnen 24 uur herstellen of blootstelling stoppen; hoog binnen 7 dagen,
middel binnen 30 dagen, laag binnen 90 dagen. Maandelijks gewone updates beoordelen.
De verantwoordelijke beheerder moet dit beleid operationeel borgen; een technische
uitzondering krijgt eigenaar, onderbouwing en einddatum. De op 1 oktober aangetroffen
PostgreSQL 17.6 moet worden getoetst aan de aangekondigde
[Supabase-beveiligingsupdate](https://supabase.com/changelog/postgres-15-19-17-11-breaking-changes).
De lokale testdatabase gebruikt eveneens 17.6 en bewijst geen platformpatchniveau.
