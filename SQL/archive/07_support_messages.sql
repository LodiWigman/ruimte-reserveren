-- ============================================================
-- WebReserv | 07_support_messages.sql
-- Vragen, klachten en verbetertips van gebruikers.
-- Run op bestaande database na de eerdere setup/migraties.
-- ============================================================

CREATE TABLE IF NOT EXISTS support_messages (
  id          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id     uuid NOT NULL DEFAULT auth.uid()
                    REFERENCES auth.users(id) ON DELETE CASCADE,
  message     text NOT NULL CHECK (char_length(message) BETWEEN 5 AND 1500),
  status      text NOT NULL DEFAULT 'open'
                    CHECK (status IN ('open', 'in_behandeling', 'afgehandeld')),
  admin_note  text CHECK (admin_note IS NULL OR char_length(admin_note) <= 500),
  handled_by  uuid REFERENCES auth.users(id),
  handled_at  timestamptz,
  created_at  timestamptz NOT NULL DEFAULT now(),
  updated_at  timestamptz NOT NULL DEFAULT now()
);

ALTER TABLE support_messages ENABLE ROW LEVEL SECURITY;

CREATE OR REPLACE FUNCTION public.set_updated_at()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = public
AS $$
BEGIN
  NEW.updated_at = now();
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS set_support_messages_updated_at ON support_messages;
CREATE TRIGGER set_support_messages_updated_at
  BEFORE UPDATE ON support_messages
  FOR EACH ROW
  EXECUTE FUNCTION public.set_updated_at();

CREATE INDEX IF NOT EXISTS idx_support_messages_user
  ON support_messages (user_id, created_at DESC);

CREATE INDEX IF NOT EXISTS idx_support_messages_status
  ON support_messages (status, created_at DESC);

DROP POLICY IF EXISTS "Gebruiker dient vraag klacht of tip in" ON support_messages;
CREATE POLICY "Gebruiker dient vraag klacht of tip in"
  ON support_messages FOR INSERT TO authenticated
  WITH CHECK (
    user_id = auth.uid()
  );

DROP POLICY IF EXISTS "Gebruiker leest eigen vragen klachten en tips" ON support_messages;
CREATE POLICY "Gebruiker leest eigen vragen klachten en tips"
  ON support_messages FOR SELECT TO authenticated
  USING (
    user_id = auth.uid()
  );

DROP POLICY IF EXISTS "Admin leest alle vragen klachten en tips" ON support_messages;
CREATE POLICY "Admin leest alle vragen klachten en tips"
  ON support_messages FOR SELECT TO authenticated
  USING (
    private.is_admin()
  );

DROP POLICY IF EXISTS "Admin behandelt vragen klachten en tips" ON support_messages;
CREATE POLICY "Admin behandelt vragen klachten en tips"
  ON support_messages FOR UPDATE TO authenticated
  USING (
    private.is_admin()
  )
  WITH CHECK (
    private.is_admin()
  );
-- ARCHIEF: NIET UITVOEREN. Actuele installatie: SQL/README.md en SQL/basis.sql.
-- Dit bestand bewaart historische ontwikkelstappen, inclusief bekende fouten.
