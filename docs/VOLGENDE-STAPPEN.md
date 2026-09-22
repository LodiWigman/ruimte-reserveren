# Jouw volgende stappen

## Nu: herstelversie in de bestaande testomgeving controleren

1. Sluit oude reserveringstabbladen. Open je gebruikelijke Vercel-website opnieuw
   en ververs volledig. Er hoeft geen SQL meer uitgevoerd te worden.
2. Log in met je bestaande Clerk-account van `lodi.wigman`. Controleer dat het
   beheerscherm zichtbaar is en dat je de 18 ruimtes ziet (waarvan één inactief).
   Is je adminrol niet zichtbaar, stop dan en meld de fout; maak geen tweede admin
   en voer de reset niet opnieuw uit.
3. Boek een vrije tijd, wijzig en annuleer die. Maak ook een korte reeks en kies
   vanaf het tweede moment ‘deze en volgende’. Het eerste moment moet blijven staan.
4. Gebruik daarnaast een apart extern testaccount in een privévenster. Controleer
   dat het als extern start, een verzoek kan indienen/wijzigen/intrekken en geen
   persoonlijke details van andere gebruikers ziet. Vraag een interne rol aan en
   behandel die als admin. Controleer daarna direct reserveren met dat account.
5. Test een reserveringsverzoek en goedkeuring/afwijzing. Probeer bij een bezette
   tijd een verzoek; goedkeuring mag geen overlappende bevestigde reservering maken.
6. Stuur een vraag, beantwoord die als admin en bekijk de reactie als gebruiker.
   Importeer een klein CSV-/Excel-bestand en een ICS uit jouw agenda. Controleer
   datum/tijd en reeksverband; dezelfde bevestigde momenten opnieuw importeren
   moet worden geweigerd. Niet-ondersteunde ICS-opties worden bewust afgewezen.
7. Herhaal de belangrijkste handelingen op je telefoon. Test verversen,
   uitloggen en opnieuw inloggen. Verwijder daarna ongewenste testreserveringen
   via de website; voer geen nieuwe database-reset uit.

## Later: van testomgeving naar echte productie

1. Regel een eigen domein en koppel het aan Vercel. Controleer DNS en HTTPS.
   Een domeinaankoop of betaald abonnement is niet onderdeel van deze release.
2. Maak voor de Clerk-app een productieomgeving. Stel het eigen domein, de gewenste
   aanmeldmethodes, redirectadressen en eventuele verificatie-instellingen in.
   Test- en productiegebruikers zijn afzonderlijk; ga niet uit van hetzelfde gebruikers-ID.
3. Richt in Supabase de Clerk-koppeling voor de productie-issuer in. Gebruik de
   officiële integratie en de vereiste `role=authenticated`-claim. Verwijder de
   huidige werkende koppeling pas na een gecontroleerde omschakeling.
4. Maak je eigen account in Clerk-productie. Geef het nieuwe, gecontroleerde Clerk-ID
   via beheer-SQL de adminrol. Hiervoor bestaat `SQL/admin.example.sql`; laat dit
   gericht uitvoeren zonder tabellen opnieuw op te bouwen. Nieuwe gebruikers blijven extern.
5. Werk de openbare Clerk-publishable key en de bijbehorende Clerk-scriptadressen
   in `index.html` bij naar de productieomgeving en publiceer via `main`.
   Deel nooit een Clerk-secret key of Supabase service-role key in de website of chat.
6. Voer de bovenstaande praktijktests opnieuw uit op het productiedomein, inclusief
   nieuwe gebruiker, adminrol, mobiel, sessievernieuwing en uitloggen.
   Spreek vóór ingebruikname af wie beheer, support en herstel van back-ups verzorgt.
   Controleer welke back-upvoorzieningen je huidige Supabase-abonnement biedt.

De herstelrelease is geen bewijs van absolute veiligheid of foutloosheid. De uitgevoerde
tests en de grenzen staan in [VERIFICATIE.md](VERIFICATIE.md).

Officiële uitleg: [Clerk-omgevingen](https://clerk.com/docs/guides/development/managing-environments)
en [Supabase met Clerk](https://supabase.com/docs/guides/auth/third-party/clerk).
