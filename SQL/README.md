# Actuele databasebasis

Gebruik de genummerde scripts in `archive/` niet voor installatie of herstel.
Die combineren verschillende ontwikkelfasen en bevatten bekende fouten.

| Bestand | Doel |
| --- | --- |
| `reset-eenmalig.sql` | Destructieve verwijdering van uitsluitend de zes bestaande applicatietabellen en geïnventariseerde oude applicatiefuncties. Alleen voor de aangetroffen oude structuur. |
| `basis.sql` | Complete Clerk-native tabellen, constraints, indexen, RLS, rechten en RPC's. Op een lege applicatiestructuur. |
| `startgegevens.sql` | De 18 gecontroleerde ruimtes, inclusief één inactieve ruimte. |
| `admin.example.sql` | Voorbeeld voor adminherstel door de databasebeheerder. |
| `admin.local.sql` | Lokaal gecontroleerd admin-ID; uitgesloten van Git. |
| `migrations/` | Toekomstige afzonderlijk gereviewde wijzigingen. |
| `migrations/20260922151039_reservation_workflows.sql` | Voorbereide gerichte vervolgwijziging: metadata, rolverzoeken, bewerken en opschonen goedgekeurde verzoeken. Geen reset. |
| `verify.sql` | Alleen-lezen controle na heropbouw. |

Reset en basis zijn bewust niet blind herhaalbaar. Een tweede uitvoering moet
stoppen. Gebruik één transactie voor reset, basis, startgegevens en adminherstel.
De reset gebruikt geen `CASCADE`: onverwachte afhankelijkheden blokkeren uitvoering.

Alle nieuwe tabellen hebben RLS en expliciete leesrechten. De browser heeft geen
INSERT/UPDATE/DELETE/TRUNCATE-grants. Mutaties lopen via public-RPC's; die controleren
identiteit, actuele applicatierol, eigenaar en status. `han_private` bevat interne
helpers en hoort niet in de blootgestelde Data API-schema's.

De RPC's gebruiken bewust `SECURITY DEFINER`, een lege `search_path` en volledig
gekwalificeerde objectnamen. Hun tabellen zijn bewust niet rechtstreeks schrijfbaar.
Uitvoeren is alleen toegekend aan `authenticated`; gevoelige functies controleren
zelf de rol. Een advisorwaarschuwing over uitvoerbare definer-functies is dus een
reviewpunt, geen reden om controles te verwijderen of tabelrechten te verruimen.
