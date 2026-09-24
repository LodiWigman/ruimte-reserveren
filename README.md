# HAN ruimtereserveringen

Eén `index.html`, Clerk voor login, Supabase/PostgreSQL voor gegevens en rechten.
Hosting via Vercel, automatisch gekoppeld aan `LodiWigman/ruimte-reserveren`, branch `main`.

Deze herstelversie is voorbereid voor de bestaande **Clerk-testomgeving**.
Productie vraagt een eigen domein, Clerk-productieconfiguratie en een gecontroleerd
nieuw admin-ID. Zie het releaseverslag voor de uitgevoerde publicatie en controles.

- [Rechten en gedrag](docs/RECHTEN-EN-GEDRAG.md)
- [Heropbouw, publicatie en herstel](docs/UITVOEREN.md)
- [Verificatie en beperkingen](docs/VERIFICATIE.md)
- [Databasebestanden](SQL/README.md)
- [Uitgevoerde release](docs/RELEASE.md)
- [Jouw volgende stappen](docs/VOLGENDE-STAPPEN.md)
- [Voorbereide verbeteringen na praktijktest](docs/VERBETERINGEN.md)

## Tests

Gebruik Node.js 24 en pnpm. De website heeft geen buildstap of framework.

```text
pnpm install --frozen-lockfile
pnpm test
node tests/setup-browser.mjs
pnpm exec playwright install chromium
pnpm test:ui
```

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
