# Rechten en productgedrag

## Rechtenmatrix

| Handeling | Uitgelogd | Extern | Intern | Admin |
| --- | --- | --- | --- | --- |
| Actieve ruimtes en geschoonde dagbezetting | Nee | Ja | Ja | Ja |
| Details bevestigde reserveringen/verzoeken | Nee | Eigen | Eigen | Alle |
| Profiel automatisch aanmaken | Nee | Eigen, altijd extern | Bestaande rol behouden | Bestaande rol behouden |
| Eigen rol rechtstreeks verhogen | Nee | Nee | Nee | Geen browserfunctie |
| Reserveringsverzoek indienen | Nee | Ja, met organisatie/gelegenheid/motivatie | Ja bij bezetting | Ja bij bezetting |
| Direct reserveren | Nee | Nee | Vrije momenten | Vrije momenten |
| Bevestigde reservering wijzigen | Nee | Nee | Eigen | Eigen |
| Bevestigde reservering annuleren | Nee | Eigen | Eigen | Alle |
| Open verzoek wijzigen/intrekken | Nee | Eigen | Eigen | Alle |
| Verzoek goedkeuren/afwijzen | Nee | Nee | Nee | Ja |
| Interne rol aanvragen | Nee | Ja, maximaal één open verzoek | Nee | Nee |
| Rolverzoek behandelen | Nee | Nee | Nee | Alleen extern → intern bij goedkeuring |
| Ruimtes beheren/importeren | Nee | Nee | Nee | Ja |
| Vraag/klacht/tip indienen en lezen | Nee | Eigen | Eigen | Eigen en alle lezen |
| Reactie/status supportbericht wijzigen | Nee | Nee | Nee | Ja |

De database handhaaft dit ook bij directe API-aanroepen. Een verborgen knop is
geen autorisatiecontrole. Rollen staan in `profiles`; Clerk levert uitsluitend
de geverifieerde tekstuele gebruikersidentiteit. Nieuwe profielen kunnen geen rol
kiezen. Het eerste adminprofiel wordt via beheer-SQL ingericht, zonder openbare
zelfpromotiefunctie. De huidige browser staat admins, net als voorheen, alleen
wijzigen van eigen bevestigde reserveringen toe; annuleren kan wel voor iedereen.

## Betrouwbaarheid

Alle bevestigde reserveringen vallen onder een PostgreSQL-exclusionconstraint per
ruimte en tijdvak. Aansluitende tijden mogen; overlap niet. Mutaties nemen daarnaast
een korte gedeelde transactielock. Dit eenvoudige ontwerp serialiseert schrijfwerk
voor dit kleine systeem. Het is geen bewijs dat grote belasting al is getest.

Een nieuwe reeks kan, net als voorheen, vrije bevestigde momenten en bezette
verzoeken bevatten. De hele inzending wordt samen vastgelegd. Goedkeuren voegt
reserveringen en behandelstatus samen in één transactie toe. Bij een conflict
blijven alle geselecteerde verzoeken open. Wijzigen en omzetten naar verzoeken
zijn eveneens atomair. Verwijderde of al behandelde items leveren een fout op.

Een netwerkfout na opslaan kan een onduidelijk resultaat geven: eerst verversen en
controleren voordat opnieuw wordt ingestuurd. Er is geen algemeen idempotentiesysteem
voor aanvragen. Een bevestigde tijd kan door de overlapconstraint niet dubbel worden
geboekt. Opnieuw importeren van bezette tijden wordt volledig geweigerd.

## Reeksen

- Iedere gebeurtenis blijft een losse rij; geen hoofdreservering of nieuw framework.
- ‘Alleen deze’ gebruikt één item. ‘Deze en volgende’ selecteert vanaf het gekozen
  item op datum en begintijd, binnen dezelfde eigenaar en reeks. Eerdere items blijven.
- Een wijziging splitst de geselecteerde gebeurtenissen af naar een nieuw reeks-ID;
  één gewijzigde gebeurtenis wordt zelfstandig. Zo gaan eerdere gebeurtenissen niet
  onbedoeld mee in een latere wijziging.
- Bevestigde reserveringen en open verzoeken blijven afzonderlijke soorten items;
  een reeksactie behandelt de geselecteerde soort. Reeds behandelde verzoeken blijven
  als historie staan. Annuleren van de bevestigde afspraak opent een oud verzoek niet.
- Maand-/jaarherhaling slaat niet-bestaande dagen over: 31 januari → 31 maart;
  29 februari → de volgende toepasselijke schrikkeldag. Geen verschuiving naar maart.
- Maximaal 520 momenten per inzending. Kalenders en tijden zijn Nederlands
  (`Europe/Amsterdam`), ook wanneer de browser een andere lokale tijdzone gebruikt.
- Niet-bestaande/dubbele kloktijden bij de overgang naar zomer-/wintertijd worden
  afgewezen. Afspraken die een daggrens overschrijden moeten vooraf per dag worden gesplitst.

## Import

CSV ondersteunt komma/puntkomma, gequote velden, dubbele aanhalingstekens en
regeleinden binnen velden. Excel ondersteunt één werkblad en numerieke datum-/tijdcellen,
inclusief het 1904-datumsysteem. Onmogelijke datums, seconden, ongeldige aantallen,
te lange teksten en niet-eenduidige ruimtes worden afgewezen; tekst wordt niet stil
afgekapt. Capaciteit blijft zoals voorheen een waarschuwing, geen harde boekingsgrens.

ICS ondersteunt UTC, `Europe/Amsterdam` en de alias `W. Europe Standard Time`.
Ondersteund: DAILY/WEEKLY/MONTHLY/YEARLY, INTERVAL, COUNT óf UNTIL, eenvoudige BYDAY
voor WEEKLY, maandag als weekbegin en EXDATE. UTC-reeksen blijven op UTC-tijd;
Nederlandse reeksen blijven op Nederlandse kloktijd. Het reeksverband blijft behouden.

Niet ondersteund: tijdzone ontbreekt/andere tijdzone, hele dagen, meerdaagse afspraken,
RECURRENCE-ID (gewijzigde individuele gebeurtenis), RDATE, EXRULE, DURATION,
BYSETPOS en overige complexe regels. Deze stoppen het volledige bestand met uitleg.
Een ICS-LOCATION moet één ruimte eenduidig aanwijzen; geen risicovolle gok op een zaal.

Import is nu alles-of-niets per bestand, maximaal 520 gebeurtenissen/5 MB. Dit is een
bewuste wijziging ten opzichte van de oude import die regels afzonderlijk oversloeg.
De preview controleert ook actuele bezetting; bij opslaan volgt de definitieve
databasecontrole. Een fout laat nul nieuwe importregels achter.

## Gegevens laden

De dagbezetting bevat uitsluitend ruimte, datum, tijden en status. Eigen en
adminlijsten laden aankomende afspraken in stabiele pagina's op ID. De pagina's lopen
door tot een lege pagina, ook als Supabase minder dan de aangevraagde 500 rijen levert.
Bij meer dan 50.000 rijen stopt de lijst met een fout; er wordt geen volledige lijst
voorgewend. De bezettingsfunctie accepteert maximaal 32 dagen en weigert meer dan
20.000 resultaten. Definitieve beschikbaarheid wordt nooit uit deze browserlijsten afgeleid.
