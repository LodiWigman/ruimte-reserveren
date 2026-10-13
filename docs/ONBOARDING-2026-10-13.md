# Introducties en hulp — lokale voorbereiding

Doel: een nieuwe bezoeker begrijpt hoe een verzoek verschilt van een bevestigde
reservering, welke rol passend is en hoe ieder tabblad werkt. Basis: GitHub main
`2449aee` (websiteblob `4b82ffaec564f689dcdc4ff575e0c35100ddf3fc`).

## Wat is toegevoegd

- Welkomstintroductie in drie stappen, plus introducties voor extern, intern en admin.
- Een uitlegkaart en optionele rondleiding van maximaal drie stappen voor ieder
  toegankelijk tabblad; zes uitklapbare toelichtingen onder Beheer.
- Vaste Hulp-knop, overslaan, opnieuw afspelen, Nederlandse en Engelse teksten.
- Tekstlegenda bij de tijdlijn, herhalingsuitleg en een blijvende uitkomst met link
  naar eigen verzoeken/reserveringen (ook naar Beheer bij reserveren voor anderen).
- Opslag per account en gids/rol. Een nieuwe rol heeft een eigen introductie.
  Ongewijzigde uitleg (zoals Overzicht en Vragen/klachten) blijft afgevinkt bij
  een rolwijziging; alleen nieuwe of gewijzigde uitleg verschijnt opnieuw.
  Gastvoortgang blijft lokaal; een zojuist bekeken gastintroductie wordt niet
  direct gevolgd door dezelfde externe basisuitleg.
- Inloggen en een verplicht profiel hebben voorrang. Uitleg wacht bij invoer;
  terugkeren naar Overzicht biedt een rustig moment voor een nieuwe rolintroductie.
- Bij accountwisseling sluiten hulpvensters en opent Overzicht met de nieuwe
  accountvoortgang. Vertraagde antwoorden van een vorig account worden genegeerd.

## Opslag en beveiliging

Nieuwe migratie: `SQL/migrations/20261013122102_help_onboarding.sql`.
De CLI heeft het bestand aangemaakt; het staat in de bestaande migratiemap.

`help_progress` bevat uitsluitend account-ID, gids-ID, afgerond/overgeslagen en
tijdstip. De samengestelde primaire sleutel voorkomt duplicaten. Toevoegen is
idempotent; apparaten schrijven geen hele gedeelde voortgangslijst over.
SELECT en INSERT zijn via RLS beperkt tot het geverifieerde eigen account, ook
voor admins. UPDATE en DELETE zijn niet aan applicatieaccounts verleend.
De twee nieuwe RPC's zijn SECURITY INVOKER en accepteren geen eigenaar-ID.
De bestaande `han_private.uid()` controleert vertrouwde sessies en blokkades.
Rollen, reserveringsregels en bestaande profielgegevens veranderen niet.

Lokale cache en nog niet gesynchroniseerde bevestigingen zijn accountgebonden.
Een ontbrekende of trage opslag blokkeert boekingen niet: na maximaal vier seconden
kan hulp met lokale voortgang doorgaan. Mislukte bevestigingen worden bij de
volgende aanmelding of een online-gebeurtenis opnieuw aangeboden. Bij een
opslagstoring kan uitleg op een ander apparaat opnieuw verschijnen; synchronisatie
kan pas na herstel. Helpvoortgang wordt nooit gebruikt voor autorisatie.

## Bekijkbaar voorbeeld

Start `node tests/help-preview.mjs` en open `http://127.0.0.1:4178/`.
De rolkiezer laat bezoeker, extern, intern en admin zien. Sluit of doorloop eerst
een open introductie om de rolkiezer te bedienen. Met Hulp is alles opnieuw te zien.
De preview gebruikt de echte gewijzigde pagina met uitsluitend fictieve gegevens.
Clerk en Supabase zijn vervangen door lokale voorbeelden; de preview blokkeert
netwerkverbindingen en schrijft geen echte boekingen. De preview is uitgesloten
van de hostingbuild. `--build-only` maakt een zelfstandig lokaal HTML-voorbeeld.

## Uitgevoerde lokale controles

Alle dertien testgroepen zijn geslaagd. Databasetests gebruikten een tijdelijke
PostgreSQL-database; browserscenario's gebruikten Edge met lokaal afgehandelde
netwerkverzoeken. Na correcties zijn de geraakte controles opnieuw uitgevoerd.

| Controle | Resultaat |
| --- | --- |
| Frontendlogica | 29 scenario's geslaagd |
| Bestaande database, workflows, reset, Connectr en overzicht/cases | Alle 5 suites geslaagd |
| Nieuwe hulpdatabase | Eigen-accountrechten, adminisolatie, anonieme weigering, invoercontrole, herhalen, gelijktijdige apparaten, rolrechten en ingetrokken sessies geslaagd |
| Bestaande gebruikersstromen | Desktop 1365 px en mobiel 390 px geslaagd |
| Formuliervalidatie | Nederlands/Engels en herstellen van invoerfouten geslaagd |
| Nieuwe hulpinterface | Eerste bezoek, overslaan, opnieuw openen, accountwisselingen, rolwisselingen, ongewijzigde uitleg, profielvoorrang, trage/defecte opslag, behoud invoer, toetsenbordfocus en alle tabs in beide talen geslaagd |
| Browserbeveiliging | XSS-varianten, CSP en afschermen van oude accountgegevens geslaagd |
| Importbeveiliging | Bestaande bestands- en limietcontroles geslaagd |
| Publicatiebuild | Alleen website/logo; gewijzigde scriptintegriteit en onverwachte bestanden blokkeren de build |

Screenshots staan in `test-results/help/`. `test-results/help/preview.html` is het
zelfstandige voorbeeld; de lokale previewserver staat op poort 4178. Deze bestanden
worden niet gepubliceerd. De exacte voorbereide bestanden en SHA-256-controlesommen
staan in `ONBOARDING-2026-10-13.manifest.json`.

De review heeft de nieuwe opslagrechten, accountwisselingen, gelijktijdige
voortgangsopslag, renderen van teksten en het behoud van bestaande formulieren
gecontroleerd. Er zijn geen bekende blokkerende bevindingen in deze wijziging.

## Publicatie na apart eindakkoord

Bestemming: `LodiWigman/ruimte-reserveren`, branch `main`, automatische Vercel-hosting
op `https://ruimte-reserveren.vercel.app/`.
Database: Supabase `han-reserveringen` (`oappvdfjyvbmvqrjvnmv`).

1. Controleer of main sinds bovenstaande basis is gewijzigd; integreer zo nodig
   relevante veranderingen en controleer de definitieve versie opnieuw.
2. Pas uitsluitend de nieuwe help_onboarding-migratie toe en controleer grants,
   RLS en de nieuwe RPC's. Geen reset en geen herhaling van oude migraties.
3. Publiceer website, bijbehorende CSP-hash, migratie, tests en documentatie.
4. Controleer de live build en test met een echte ingelogde gebruiker de
   introductie en accountvoortgang op twee apparaten.

Deze voorbereiding geeft geen toestemming voor pushen of live databasewijzigingen.
De live aanmelding en apparaatoverschrijdende opslag worden pas na publicatie
met echte accounts getest; lokale tests gebruiken fictieve identiteiten.
