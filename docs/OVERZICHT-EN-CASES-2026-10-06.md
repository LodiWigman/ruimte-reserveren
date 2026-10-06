# Voorbereide verbeteringen — 6 oktober 2026

Status: lokaal voorbereid; nog niet gepubliceerd en de live database is niet gewijzigd.
Bestemming na afzonderlijke eindgoedkeuring: `LodiWigman/ruimte-reserveren`, branch
`main`, automatische Vercel-publicatie op https://ruimte-reserveren.vercel.app/.
Database: Supabase `han-reserveringen` (`oappvdfjyvbmvqrjvnmv`).

## Inhoud

1. Beheerders kunnen vanuit de reservering in het overzicht dezelfde overdracht
   starten als in Beheer, inclusief ontvanger, controle, moment/reeks en bevestiging.
   De overdrachtknop blijft ook na opnieuw renderen van beheerschermen beschikbaar.
2. Overlappende reserveringen en verzoeken krijgen afzonderlijke rijen. Op mobiel
   staan items over de volle breedte onder elkaar, met hun tijden en type.
3. Het bestaande, volledige UUID is het casenummer. Het staat in de bevestiging,
   de persoonlijke en beheerdersoverzichten en het gesprek, met een kopieerknop.
4. Beheerders zoeken op casenummer (ook gedeeltelijk, hoofdletterongevoelig en in
   het archief) en combineren dat met type en status. Filters zijn te wissen.
5. Afgehandelde meldingen kunnen rechtstreeks naast Gesprek openen worden
   gearchiveerd. Dit ondersteunt naast klachten ook vragen en tips, overeenkomstig
   de bestaande gespreksfunctie.
6. Opslaan en archiveren hebben een contrastrijke roze achtergrond, met herkenbare
   focus- en uitgeschakelde toestanden.
7. Archiveren slaat in dezelfde databasetransactie een blijvende notificatie op.
   Deze noemt expliciet de archivering, het type en het casenummer. Een herhaalde
   poging met een verouderde versie maakt geen dubbele notificatie.
8. Alle reserveringen heeft dropdowns voor naam, ruimte en reserveringsdatum.
9. Mijn verzoeken/reserveringen heeft dropdowns voor type, ruimte en datum.
10. Organisatie/afdeling is verplicht bij het aanmaken van reserveringen en
    verzoeken, voor alle rollen. Dat wordt in het formulier en bij de daadwerkelijke
    databaseopslag afgedwongen; beschikbaarheidscontroles blijven zonder dit veld
    bruikbaar. Imports accepteren een organisatiekolom of expliciet ingevulde
    standaardorganisatie. Interne gebruikers en beheerders zien de organisatie in
    het overzicht. Externen krijgen geen extra gegevens over anderen.

## Database en bestaande gegevens

Nieuwe migratie: `SQL/migrations/20261006110904_overview_cases_filters.sql`.
Vereist de reeds gepubliceerde Connectr-migratie. Voer geen reset, basisinstallatie
of oude migratie opnieuw uit. De migratie wijzigt de bezettingsprojectie en
archiefhandeling en voegt twee triggers toe voor organisatievalidatie.

De opdrachtgever heeft aangegeven dat de huidige inhoud testgegevens is en niet
behouden hoeft te blijven. Verwijdering is niet nodig voor deze update en maakt
geen deel uit van deze publicatie. Bestaande IDs blijven behouden. Oude boekingen
zonder organisatie blijven zichtbaar en overdraagbaar. Bij inhoudelijk wijzigen
via het formulier wordt gevraagd de organisatie aan te vullen; ook een oud verzoek
zonder organisatie moet die informatie krijgen voordat het kan worden goedgekeurd.

De website en databasewijziging moeten kort na elkaar worden gepubliceerd.
Gebruikers met een oud tabblad moeten de website verversen om de nieuwe bediening
te zien. De bestaande Clerk-configuratie blijft gebruikt.

## Controle

- 29 frontendscenario's: onder meer intervalindeling, gecombineerde filters,
  archiefzoekopdrachten, imports en de inhoud van de archiefnotificatie.
  Ook vertraagde gesprekresultaten en verversen tijdens een gesprekshandeling
  zijn gecontroleerd, zodat opgeslagen statussen niet worden teruggezet.
- 7 gerichte databasescenario's: behoud IDs, verplichte organisatie voor alle rollen,
  beperkte zichtbaarheid, geweigerde toegang, rollback bij notificatiefout,
  herhaalde archivering en notificatie aan een beheerder die zelf indiener is.
- Bestaande beveiligingssuite op de nieuwe databaseversie: rolmisbruik, vreemde
  IDs, directe tabeltoegang, afgeschermde hulpfuncties, quotas en sessie-intrekking.
- Browserbeveiliging: vijf XSS-varianten, CSP, toegestane schermacties en uitloggen.
- Importbeveiliging: 15 bestandsscenario's, waaronder ongeldige en te grote bestanden.
- Nederlandse/Engelse formuliervalidatie en publicatiebuild gecontroleerd.
- Volledige schermcontrole geslaagd op 1365 en 390 pixels breed: overdracht vanuit
  het overzicht, gecombineerde filters, casenummerbevestiging, rechtstreeks
  archiveren, notificatie aan de indiener en drie overlappende items. De mobiele
  controle is afzonderlijk herhaald na het aanscherpen van de testselectie.
  Schermafbeeldingen staan lokaal onder `test-results/overlap-1365.png` en
  `test-results/overlap-390.png`; de schermindeling is visueel gecontroleerd.

Tests gebruiken een lokale wegwerpdatabase, fictieve gebruikers en een gesimuleerde
Clerk-sessie. Er is geen echte gebruikerssessie of live schrijfhandeling gebruikt.
Na goedgekeurde publicatie moeten de live migratie en publicatie worden geverifieerd.
De bestaande paginering wordt gebruikt om alle relevante meldingen te laden;
filteren gebeurt in de browser. Zeer grote historische datasets zijn niet belast getest.

## Publicatiegrens

De bronbestanden zijn vergeleken met GitHub-commit
`af404124a239910590d78468c8911eeac03b366f`. Alleen de bestanden van deze wijziging
mogen worden gepubliceerd; de werkmap bevat daarnaast eerdere lokale Git-wijzigingen.
Een afzonderlijk manifest legt de uiteindelijke goed te keuren bestandsversies vast.
