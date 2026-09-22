-- ============================================================
-- WebReserv | 06_policies.sql
-- Row Level Security en policies.
-- Run na: 05_triggers.sql
-- ============================================================

ALTER TABLE profiles               ENABLE ROW LEVEL SECURITY;
ALTER TABLE rooms                  ENABLE ROW LEVEL SECURITY;
ALTER TABLE reserveringen          ENABLE ROW LEVEL SECURITY;
ALTER TABLE role_requests          ENABLE ROW LEVEL SECURITY;
ALTER TABLE reserveringsverzoeken  ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Gebruiker leest eigen profiel"
  ON profiles FOR SELECT TO authenticated
  USING (id = auth.uid());

CREATE POLICY "Admin leest alle profielen"
  ON profiles FOR SELECT TO authenticated
  USING (private.is_admin());

CREATE POLICY "Admin past profielen aan"
  ON profiles FOR UPDATE TO authenticated
  USING (private.is_admin())
  WITH CHECK (private.is_admin());

CREATE POLICY "Iedereen ziet actieve ruimtes"
  ON rooms FOR SELECT TO authenticated
  USING (active = true OR private.is_admin());

CREATE POLICY "Admin voegt ruimtes toe"
  ON rooms FOR INSERT TO authenticated
  WITH CHECK (private.is_admin());

CREATE POLICY "Admin past ruimtes aan"
  ON rooms FOR UPDATE TO authenticated
  USING (private.is_admin())
  WITH CHECK (private.is_admin());

CREATE POLICY "Admin verwijdert ruimtes"
  ON rooms FOR DELETE TO authenticated
  USING (private.is_admin());

CREATE POLICY "Iedereen ziet reserveringen"
  ON reserveringen FOR SELECT TO authenticated
  USING (true);

CREATE POLICY "Intern en admin mogen reserveren"
  ON reserveringen FOR INSERT TO authenticated
  WITH CHECK (user_id = auth.uid() AND private.is_intern());

CREATE POLICY "Admin maakt reserveringen namens aanvragers"
  ON reserveringen FOR INSERT TO authenticated
  WITH CHECK (private.is_admin());

CREATE POLICY "Gebruiker annuleert eigen reservering"
  ON reserveringen FOR DELETE TO authenticated
  USING (user_id = auth.uid());

CREATE POLICY "Admin verwijdert alle reserveringen"
  ON reserveringen FOR DELETE TO authenticated
  USING (private.is_admin());

CREATE POLICY "Gebruiker ziet eigen rolverzoeken"
  ON role_requests FOR SELECT TO authenticated
  USING (user_id = auth.uid());

CREATE POLICY "Admin ziet alle rolverzoeken"
  ON role_requests FOR SELECT TO authenticated
  USING (private.is_admin());

CREATE POLICY "Extern dient rolverzoek in"
  ON role_requests FOR INSERT TO authenticated
  WITH CHECK (
    user_id = auth.uid()
    AND NOT private.is_intern()
  );

CREATE POLICY "Gebruiker trekt eigen verzoek in"
  ON role_requests FOR DELETE TO authenticated
  USING (user_id = auth.uid() AND status = 'pending');

CREATE POLICY "Admin behandelt rolverzoeken"
  ON role_requests FOR UPDATE TO authenticated
  USING (private.is_admin())
  WITH CHECK (private.is_admin());

CREATE POLICY "Gebruiker ziet eigen reserveringsverzoeken"
  ON reserveringsverzoeken FOR SELECT TO authenticated
  USING (user_id = auth.uid());

CREATE POLICY "Admin ziet alle reserveringsverzoeken"
  ON reserveringsverzoeken FOR SELECT TO authenticated
  USING (private.is_admin());

CREATE POLICY "Iedereen dient reserveringsverzoek in"
  ON reserveringsverzoeken FOR INSERT TO authenticated
  WITH CHECK (user_id = auth.uid());

CREATE POLICY "Gebruiker wijzigt eigen open reserveringsverzoek"
  ON reserveringsverzoeken FOR UPDATE TO authenticated
  USING (user_id = auth.uid() AND status = 'pending')
  WITH CHECK (user_id = auth.uid() AND status = 'pending');

CREATE POLICY "Gebruiker trekt eigen reserveringsverzoek in"
  ON reserveringsverzoeken FOR DELETE TO authenticated
  USING (user_id = auth.uid() AND status = 'pending');

CREATE POLICY "Admin verwijdert reserveringsverzoeken"
  ON reserveringsverzoeken FOR DELETE TO authenticated
  USING (private.is_admin());

CREATE POLICY "Admin behandelt reserveringsverzoeken"
  ON reserveringsverzoeken FOR UPDATE TO authenticated
  USING (private.is_admin())
  WITH CHECK (private.is_admin());
-- ARCHIEF: NIET UITVOEREN. Actuele installatie: SQL/README.md en SQL/basis.sql.
-- Dit bestand bewaart historische ontwikkelstappen, inclusief bekende fouten.
