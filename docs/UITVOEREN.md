# Uitvoer- en herstelprocedure

## Voorbereide versie

Bron: GitHub `LodiWigman/ruimte-reserveren`, `main`, commit
`2adcf4a06724c140278e239a275f0f78cdcb9496`, plus de live Supabase-definities van
22 september 2026. Supabase: `han-reserveringen`, `oappvdfjyvbmvqrjvnmv`.
Hosting: Vercel, automatisch gekoppeld aan GitHub `main`, door de gebruiker bevestigd
bij laatste goedkeuring op 22 september 2026. De gebruiker heeft uitdrukkelijk gevraagd
Vercel niet te controleren. GitHub en Supabase worden wel gecontroleerd.

Deze documenten geven geen toestemming voor uitvoering. Eerst het volledige
wijzigingsoverzicht en expliciete laatste goedkeuring van de gebruiker. Bij een
inhoudelijk gewijzigde versie opnieuw een bijgewerkt overzicht en goedkeuring.

## Wat verdwijnt en terugkomt

Bij inspectie: 2 profielen, 2 reserveringen, 1 reserveringsverzoek, 1 rolverzoek,
1 supportbericht en 18 ruimtes. Alle oude applicatierijen worden verwijderd.
De 18 gecontroleerde ruimtes komen terug (17 actief, W0.02 inactief). Het gecontroleerde
enige adminprofiel `lodi.wigman` wordt in dezelfde transactie opnieuw aangemaakt.
Het concrete Clerk-ID staat uitsluitend in `SQL/admin.local.sql` en de lokale
inspectiegegevens. De andere gebruiker krijgt bij opnieuw inloggen een extern profiel.

Clerk-accounts, Supabase Auth, Storage, systeemtabellen, extensies en andere projecten
worden niet gewist. De reset verwijdert alleen benoemde applicatieobjecten.
Er zijn geen Supabase Edge Functions aangetroffen. De huidige website gebruikt
geen van de obsolete goedkeuringsfuncties die verwijderd worden.

## Na laatste goedkeuring, in deze volgorde

1. Controleer opnieuw repository/branch/HEAD, project-ID, adminprofiel, ruimtes,
   afhankelijkheden en gegevensaantallen. Bij afwijkingen eerst gevolgen beoordelen.
   Bewaar een verse lokale, niet-gepubliceerde kopie van alle zes tabellen en het
   volledige objectcatalogusrapport (constraints, functies, triggers, policies, grants).
2. Publiceer tijdelijk de voorbereide `release/onderhoud.html` als `index.html` op
   `main` en controleer de inhoud op GitHub. Vercel neemt deze automatisch over.
   Op verzoek van de gebruiker wordt de Vercel-deployment niet gecontroleerd;
   er wordt dus niet vastgesteld wanneer de onderhoudspagina daadwerkelijk zichtbaar is.
   Dit is onderdeel van dezelfde vooraf goed te keuren publicatie. Laat geen
   reserveringsschermen openstaan. Oude tabbladen kunnen na de reset niet rechtstreeks
   schrijven, omdat de nieuwe tabelgrants die oude schrijfroutes blokkeren.
3. Stel één gecontroleerde migratie samen uit `SQL/reset-eenmalig.sql`, `SQL/basis.sql`,
   `SQL/startgegevens.sql` en het gecontroleerde `SQL/admin.local.sql`. Pas deze via de
   Supabase-connector `apply_migration` toe onder de naam `han_clerk_rebuild`.
   `node tests/prepare-release.mjs` maakt het lokale migratiebestand. De gehele
   heropbouw staat in één atomair DO-statement; succes en rollback van dit exacte
   uitvoerbestand zijn aanvullend lokaal getest. Geen losse handmatige stappen.
4. Controleer migratiehistorie, `SQL/verify.sql`, adminrol, ruimtes, grants en advisors.
   Stop bij afwijkingen; verruim nooit rechten om een controle te omzeilen.
5. Publiceer de voorbereide definitieve `index.html`, actuele SQL, documentatie en
   tests naar `main`. Neem alleen de bedoelde bestanden mee. Geen `admin.local.sql`,
   lokale back-up, node_modules, testdatabase of screenshots publiceren.
6. Controleer GitHub-commit en vergelijk de HTML op `main` met de release.
   Een push alleen bewijst geen geslaagde deployment. Op uitdrukkelijk verzoek
   blijft controle van Vercel buiten scope; rapporteer deze grens duidelijk.
7. Voer de eigen-login-praktijktests uit. Deze release blijft een testomgeving zolang
   Clerk development wordt gebruikt. Meld resterende launchstappen expliciet.

## Herstel bij problemen

De lege opbouw en een rollback van de gehele resettransactie zijn lokaal getest.
Vóór commit herstelt een rollback de oude structuur en gegevens. Voer bij een
misgelopen migratie eerst alleen-lezen controle uit; neem niet aan dat niets is toegepast.

Na commit niet blind opnieuw resetten of alleen oude HTML terugzetten: oude code en
nieuwe rechten passen niet bij elkaar. Laat de onderhoudspagina staan en herstel bij
voorkeur vooruit met een afzonderlijk geteste migratie. Moet de oude versie toch terug,
herstel dan zowel de vooraf bewaarde applicatiestructuur/data als de bijbehorende oude
website onder onderhoud. De oude versie bevat de beschreven rechtenfouten en is dus
geen geschikte productielaunch. Herstel geen volledig Supabase-project als alleen de
applicatiestructuur moet worden hersteld. De lokale snapshot is geen beheerde
Supabase-back-up; controleer daarvoor apart de beschikbare projectback-ups.

## Echte productie, later

De huidige `pk_test_…` is een openbare ontwikkelsleutel, geen gelekte geheime sleutel.
Volgens [Clerk-omgevingen](https://clerk.com/docs/guides/development/managing-environments)
zijn development en production afzonderlijke omgevingen; gebruikers gaan niet
automatisch mee. Regel eerst het eigen domein en DNS, de Clerk-productieomgeving,
de gewenste aanmeldmethodes en een werkende testlogin met het nieuwe account.

Koppel de productie-issuer via de [Supabase Clerk-integratie](https://supabase.com/docs/guides/auth/third-party/clerk),
met de claim `role=authenticated`. Zet het nieuwe, gecontroleerde Clerk-ID via
beheer-SQL op admin vóór omschakelen. Vervang daarna de openbare publishable key,
controleer toegestane domeinen/redirects en test echte login, tokenverversing en logout.
Verwijder geen ontwikkelaccounts om dit te bereiken. Nieuwe betaalde diensten of
een domeinaankoop vereisen eerst een aparte keuze van de gebruiker.
