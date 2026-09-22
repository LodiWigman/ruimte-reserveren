# Onderzoek en uitgevoerde aanpak

Onderzocht op 22 september 2026: volledige actuele GitHub-websitebron; alle lokale
SQL 01–13; live tabellen, kolommen, constraints, indexen, functies, triggers, policies,
grants, migratiehistorie, adminprofiel, ruimtes, advisors en Edge Functions.
Lokale websitekopieën zijn niet als bron gebruikt. De release begon vanaf een verse
kopie van GitHub `main`. Live SQL en GitHub zijn tijdens voorbereiding alleen gelezen.

## Bevestigde bevindingen

- De vier eerder genoemde insert/update-policies ontbreken live.
- `private.assert_admin()` verwijst naar het ontbrekende `public.is_admin()`;
  de oude approve/reject-RPC's naar het ontbrekende `public.assert_admin()`.
- De profiel-insertpolicy controleert alleen het eigen ID. Met de bestaande grants
  kan een gebruiker zonder profiel een adminrol meegeven. Dit is een echte fout.
- RLS staat aan op alle zes tabellen. Overlapconstraint, tijdvolgorde en bestaande
  tekstgrenzen zijn aanwezig. De live database bevat aanvullende updated_at-triggers
  en reeks/datum-indexen. De migratiehistorie bevat alleen `20260820163438`.
- Website-updates controleren vaak alleen `error`, niet het aantal gewijzigde rijen.
  Reeksacties en goedkeuring bestaan uit losse browseropdrachten.
- Reserveringslijsten zijn onbegrensd en hebben geen complete paginering. Reeksannuleren
  verwijdert alle datums. Maand-/jaarherhaling verschuift ongeldige dagen.
- De oude ICS-parser verliest tijdzone/uitzonderingen en het gegenereerde reeks-ID.
  De CSV-parser splitst eerst op regeleinden. Datum/tijdvalidatie accepteert ongeldige
  waarden. De oude import kan een gedeeltelijke reeks opslaan.
- De website gebruikt een Clerk-testkey. De gebruiker heeft bevestigd nog geen eigen
  productiedomein/Clerk-productieomgeving te hebben. Bij goedkeuring is verduidelijkt
  dat Vercel de actieve hosting verzorgt, automatisch gekoppeld aan GitHub `main`.
- Aanvullend: een vrij bewerkbaar ruimte-ID werd rechtstreeks in een inline
  JavaScript-string gezet. HTML-escaping alleen was daarvoor onvoldoende. Dit gebruikt
  nu afzonderlijke JSON-string- en HTML-escaping, met een browserregressietest.

## Uitgevoerde volgorde en afhankelijkheden

1. Gecontroleerde bron en lokale inspectiesnapshots vastgelegd; één admin geïdentificeerd.
2. Nieuwe Clerk-native basis met dezelfde zes tabellen ontworpen; betrouwbare writes
   en minimale bezettingsgegevens via RPC, beperkte grants/RLS.
3. Reset, basis, gecontroleerde startgegevens en lokaal adminherstel gescheiden.
4. Bestaande HTML aangesloten op het nieuwe contract; vormgeving en architectuur behouden.
5. Herhalingen/import gevalideerd en oude browsertransacties vervangen.
6. PostgreSQL 17.6 lokaal geïnstalleerd voor wegwerptests, zonder betaald cloudproject.
7. Rechten/gedrag, gelijktijdigheid, rollback, complete reset, frontend en browser getest.
8. Rechtenmatrix, publicatievolgorde, testbeperkingen en productiepad vastgelegd.

De productwijzigingen zijn expliciet beschreven in RECHTEN-EN-GEDRAG.md:
alles-of-niets import, consistente deze-en-volgende-reeksacties, overslaan van
ongeldige maanddagen, zichtbare afwijzing van niet-ondersteunde imports en een
werkende adminreactie op supportberichten. De capaciteitswaarschuwing blijft behouden.

De voorbereiding eindigt bij het goedkeuringsverzoek. Reset en publicatie blijven
afhankelijk van laatste expliciete goedkeuring van deze concrete versie.
