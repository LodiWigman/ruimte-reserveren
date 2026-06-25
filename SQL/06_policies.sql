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
  USING (public.is_admin());

CREATE POLICY "Admin past profielen aan"
  ON profiles FOR UPDATE TO authenticated
  USING (public.is_admin())
  WITH CHECK (public.is_admin());

CREATE POLICY "Iedereen ziet actieve ruimtes"
  ON rooms FOR SELECT TO authenticated
  USING (active = true OR public.is_admin());

CREATE POLICY "Admin voegt ruimtes toe"
  ON rooms FOR INSERT TO authenticated
  WITH CHECK (public.is_admin());

CREATE POLICY "Admin past ruimtes aan"
  ON rooms FOR UPDATE TO authenticated
  USING (public.is_admin())
  WITH CHECK (public.is_admin());

CREATE POLICY "Admin verwijdert ruimtes"
  ON rooms FOR DELETE TO authenticated
  USING (public.is_admin());

CREATE POLICY "Iedereen ziet reserveringen"
  ON reserveringen FOR SELECT TO authenticated
  USING (true);

CREATE POLICY "Intern en admin mogen reserveren"
  ON reserveringen FOR INSERT TO authenticated
  WITH CHECK (user_id = auth.uid() AND public.is_intern());

CREATE POLICY "Gebruiker annuleert eigen reservering"
  ON reserveringen FOR DELETE TO authenticated
  USING (user_id = auth.uid());

CREATE POLICY "Admin verwijdert alle reserveringen"
  ON reserveringen FOR DELETE TO authenticated
  USING (public.is_admin());

CREATE POLICY "Gebruiker ziet eigen rolverzoeken"
  ON role_requests FOR SELECT TO authenticated
  USING (user_id = auth.uid());

CREATE POLICY "Admin ziet alle rolverzoeken"
  ON role_requests FOR SELECT TO authenticated
  USING (public.is_admin());

CREATE POLICY "Extern dient rolverzoek in"
  ON role_requests FOR INSERT TO authenticated
  WITH CHECK (
    user_id = auth.uid()
    AND NOT public.is_intern()
  );

CREATE POLICY "Gebruiker trekt eigen verzoek in"
  ON role_requests FOR DELETE TO authenticated
  USING (user_id = auth.uid() AND status = 'pending');

CREATE POLICY "Gebruiker ziet eigen reserveringsverzoeken"
  ON reserveringsverzoeken FOR SELECT TO authenticated
  USING (user_id = auth.uid());

CREATE POLICY "Admin ziet alle reserveringsverzoeken"
  ON reserveringsverzoeken FOR SELECT TO authenticated
  USING (public.is_admin());

CREATE POLICY "Iedereen dient reserveringsverzoek in"
  ON reserveringsverzoeken FOR INSERT TO authenticated
  WITH CHECK (user_id = auth.uid());

CREATE POLICY "Gebruiker trekt eigen reserveringsverzoek in"
  ON reserveringsverzoeken FOR DELETE TO authenticated
  USING (user_id = auth.uid() AND status = 'pending');

CREATE POLICY "Admin verwijdert reserveringsverzoeken"
  ON reserveringsverzoeken FOR DELETE TO authenticated
  USING (public.is_admin());
