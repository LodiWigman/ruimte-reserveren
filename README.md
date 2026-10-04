# HAN ruimtereserveringen

Eén `index.html`, Clerk voor login, Supabase/PostgreSQL voor gegevens en rechten.
Hosting via Vercel, automatisch gekoppeld aan `LodiWigman/ruimte-reserveren`, branch `main`.

**Voorbereid voor eindgoedkeuring:** zie [het actuele publicatieoverzicht](docs/PUBLICATIEKLAAR-2026-10-01.md).
De opdrachtgever heeft het voortzetten van de bestaande **Clerk-testomgeving**
bevestigd. Het officiële adres
is https://ruimte-reserveren.vercel.app/. Bestaande accountkoppelingen blijven behouden.
De historische beveiligingsverslagen zijn geen actieve publicatievoorwaarden.

- [Rechten en gedrag](docs/RECHTEN-EN-GEDRAG.md)
- [Heropbouw, publicatie en herstel](docs/UITVOEREN.md)
- [Verificatie en beperkingen](docs/VERIFICATIE.md)
- [Databasebestanden](SQL/README.md)
- [Uitgevoerde release](docs/RELEASE.md)
- [Jouw volgende stappen](docs/VOLGENDE-STAPPEN.md)
- [HAN@Connectr: voorbereide versie en publicatievolgorde](docs/CONNECTR-OPLEVERING.md)
- [Voorbereide verbeteringen na praktijktest](docs/VERBETERINGEN.md)

## Tests

Gebruik Node.js 24 en pnpm. De website heeft geen framework. De publicatiebuild
controleert scriptintegriteit en hostingbeleid en kopieert uitsluitend website en
logo naar `dist`. De bestaande Clerk-testomgeving wordt ondersteund.

```text
pnpm install --frozen-lockfile
pnpm test
node tests/setup-browser.mjs
pnpm exec playwright install chromium
pnpm test:ui
pnpm test:security
pnpm security:gate
```

`node tests/verify-local.mjs` draait alle lokale suites na elkaar en bewaart de
testuitkomsten met bronhashes. `security:gate` voert de praktische buildcontrole uit.
`node tests/release-build.mjs` controleert de uitvoer en weigering van onveilige
of onverwachte publicatiebestanden. `node tests/clerk-smoke.mjs` test via internet
de echte openbare Clerk-vensters zonder accountregistratie of aanmelding.

Installatie en browser-setup downloaden openbare software. De tests gebruiken
uitsluitend een lokale wegwerpdatabase en fictieve gebruikers. Geen Supabase-toegang
of geheime sleutels nodig. PostgreSQL luistert alleen op 127.0.0.1:55439 en stopt
na de test. Testgegevens blijven onder `.test-data/`; sluit actieve tests voordat
je die map zelf opruimt. Resultaten/screenshots onder `test-results/` zijn niet
bedoeld voor publicatie.

Op Windows kan een aanwezige Edge-browser worden gebruikt met de omgevingsvariabele
`TEST_BROWSER_CHANNEL=msedge`. De browsercontrole gebruikt de echte websitecode en
Supabase SDK, met een nagebootste Clerk-sessie en lokale HTTP-naar-SQL-vertaling.

## Sleutels

De openbare Supabase anon-key en Clerk publishable key horen in de browser.
Ze geven op zichzelf geen beheerrechten. Gebruik hier nooit een Supabase
service-role/secret key of Clerk secret key. Rollen komen uitsluitend uit `profiles`,
niet uit door gebruikers bewerkbare Clerk-metadata.
