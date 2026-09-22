# Voorbereide release ter goedkeuring

Bestemming: bestaand Supabase-project `han-reserveringen` (`oappvdfjyvbmvqrjvnmv`)
en GitHub `LodiWigman/ruimte-reserveren`, branch `main`, met automatische Vercel-hosting.
Geen live wijzigingen of push uitgevoerd tijdens voorbereiding.

Laatste akkoord ontvangen op 22 september 2026. De gebruiker heeft Vercel als actieve
host verduidelijkt en expliciet gevraagd de Vercel-deployment niet te controleren.
De uitvoering controleert GitHub en Supabase; de eigen-logincontrole blijft nodig.

## Wijzigingen

- Nieuwe Clerk-native databasebasis met zes applicatietabellen, expliciete RLS/grants,
  betrouwbare overlapbeveiliging, validatie en tijdstempels. Veilige profielaanmaak
  uitsluitend als extern; geen browserroute om jezelf admin te maken.
- Gecontroleerde transacties voor reserveren, wijzigen, annuleren, omzetten,
  goedkeuren/afwijzen, rollen, ruimtes en import. Geen schijnsucces bij nul rijen.
- De bestaande vormgeving en één `index.html` blijven. De website gebruikt de nieuwe
  contracten, geschoonde dagbezetting, volledige paginering en databasecontrole van
  beschikbaarheid. Bewerkbare ruimte-ID's worden correct ge-escaped.
- Reeksacties zijn consequent ‘alleen deze’ of ‘deze en volgende’. Eerdere
  gebeurtenissen blijven staan; ongeldige maand-/jaardagen worden overgeslagen.
- CSV-/Excel-/ICS-validatie, Nederlandse tijdzone, ondersteunde herhalingen/EXDATE
  en behoud van reeksverband. Niet-ondersteunde gevallen geven een fout.
  Import verandert naar alles-of-niets per bestand; maximaal 520 momenten/5 MB.
- Admins kunnen supportberichten daadwerkelijk beantwoorden en hun status wijzigen.
  Scriptversies zijn vastgezet; mobiele importlayout en formulierlabels verbeterd.
- Actuele SQL, archief, rechtenmatrix, tests, onderhoudspagina en uitvoer-/herstel-
  instructies zijn gezamenlijk voorbereid in deze repository.

## Gegevensverlies en toegang

De huidige 2 profielen, 2 reserveringen, 1 reserveringsverzoek, 1 rolverzoek en
1 supportbericht verdwijnen. De 18 ruimtes worden opnieuw ingericht met de
gecontroleerde bestaande waarden (17 actief, 1 inactief). Het enige gecontroleerde
adminprofiel `lodi.wigman` wordt met hetzelfde Clerk-ID binnen dezelfde transactie
hersteld. Andere gebruikers starten bij opnieuw inloggen als extern.

Clerk-accounts en Supabase-systeemonderdelen blijven behouden. Er is een lokale
back-up van de applicatiegegevens buiten de publicatiemap; vlak vóór uitvoering
wordt deze ververst en worden admin/bron/schema opnieuw gecontroleerd.

## Controles en grenzen

Geslaagd: 17 frontend-, 19 database- en 2 reset-/herstelcontroles, plus uitgebreide
browserproeven op desktop en mobiel. Getest zijn onder meer verboden rolverhoging,
privacy, gelijktijdige reserveringen, rollback van reeksgoedkeuring/wijziging/import,
CSV/Excel, dubbele import en de belangrijkste schermhandelingen.

Echte Clerk-login/Supabase-tokenvalidatie moet na publicatie nog met eigen accounts
worden getest. Geen volledige belastingtest of onafhankelijke pentest uitgevoerd.
De huidige Clerk-testomgeving blijft in gebruik; een echte productielaunch vereist
later het eigen domein en Clerk-productieconfiguratie. Zie VERIFICATIE.md voor de
praktijktestlijst en alle concrete grenzen.

## Gevraagde laatste toestemming

Goedkeuring betreft de beschreven versie: tijdelijk onderhoud publiceren, de
applicatiedatabase in één transactie heropbouwen inclusief adminherstel, de
definitieve bestanden naar `main` publiceren en GitHub en de Supabase-inrichting
verifiëren. Vercel publiceert automatisch; de gebruiker heeft controle daarvan
buiten de uitvoerscope geplaatst. Dit is een herstelpublicatie in de huidige
testomgeving; er worden geen nieuwe betaalde diensten aangemaakt.
