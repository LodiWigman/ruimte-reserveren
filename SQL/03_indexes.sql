-- ============================================================
-- WebReserv | 03_indexes.sql
-- Indexes voor snelheid en unieke openstaande verzoeken.
-- Run na: 02_tables.sql
-- ============================================================

CREATE INDEX idx_reserveringen_recurrence_id
  ON reserveringen (recurrence_id)
  WHERE recurrence_id IS NOT NULL;

CREATE UNIQUE INDEX idx_one_pending_role_request
  ON role_requests (user_id)
  WHERE status = 'pending';

CREATE INDEX idx_reserveringsverzoeken_status
  ON reserveringsverzoeken (status)
  WHERE status = 'pending';

CREATE INDEX idx_reserveringsverzoeken_user
  ON reserveringsverzoeken (user_id);

CREATE INDEX idx_reserveringsverzoeken_recurrence_id
  ON reserveringsverzoeken (recurrence_id)
  WHERE recurrence_id IS NOT NULL;
