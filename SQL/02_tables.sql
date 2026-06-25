-- ============================================================
-- WebReserv | 02_tables.sql
-- Tabellen voor profielen, ruimtes, reserveringen en verzoeken.
-- Run na: 01_extensions.sql
-- ============================================================

CREATE TABLE profiles (
  id           uuid PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
  display_name text,
  role         text NOT NULL DEFAULT 'extern'
                    CHECK (role IN ('extern', 'intern', 'admin')),
  created_at   timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE rooms (
  id         text PRIMARY KEY,
  name       text NOT NULL,
  capacity   integer CHECK (capacity IS NULL OR capacity > 0),
  notes      text,
  active     boolean NOT NULL DEFAULT true,
  created_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE reserveringen (
  id             uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id        uuid NOT NULL DEFAULT auth.uid()
                      REFERENCES auth.users(id) ON DELETE CASCADE,
  name           text NOT NULL CHECK (char_length(name) BETWEEN 2 AND 120),
  room_id        text NOT NULL REFERENCES rooms(id),
  date           date NOT NULL,
  start_time     time NOT NULL,
  end_time       time NOT NULL,
  persons        integer CHECK (persons IS NULL OR persons > 0),
  description    text CHECK (description IS NULL OR char_length(description) <= 500),
  recurrence_id  uuid DEFAULT NULL,
  created_at     timestamptz NOT NULL DEFAULT now(),

  CHECK (start_time < end_time),

  EXCLUDE USING gist (
    room_id WITH =,
    tsrange(
      (date + start_time)::timestamp,
      (date + end_time)::timestamp,
      '[)'
    ) WITH &&
  )
);

CREATE TABLE role_requests (
  id           uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id      uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  full_name    text NOT NULL CHECK (char_length(full_name) BETWEEN 2 AND 120),
  job_title    text NOT NULL CHECK (char_length(job_title) BETWEEN 2 AND 120),
  motivation   text NOT NULL CHECK (char_length(motivation) BETWEEN 2 AND 500),
  status       text NOT NULL DEFAULT 'pending'
                    CHECK (status IN ('pending', 'approved', 'rejected')),
  handled_by   uuid REFERENCES auth.users(id),
  handled_at   timestamptz,
  created_at   timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE reserveringsverzoeken (
  id             uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id        uuid NOT NULL DEFAULT auth.uid()
                      REFERENCES auth.users(id) ON DELETE CASCADE,
  name           text NOT NULL CHECK (char_length(name) BETWEEN 2 AND 120),
  room_id        text NOT NULL REFERENCES rooms(id),
  date           date NOT NULL,
  start_time     time NOT NULL,
  end_time       time NOT NULL,
  persons        integer CHECK (persons IS NULL OR persons > 0),
  description    text CHECK (description IS NULL OR char_length(description) <= 500),
  organization   text CHECK (organization IS NULL OR char_length(organization) <= 120),
  occasion       text CHECK (occasion IS NULL OR char_length(occasion) <= 120),
  motivation     text CHECK (motivation IS NULL OR char_length(motivation) <= 500),
  recurrence_id  uuid DEFAULT NULL,
  status         text NOT NULL DEFAULT 'pending'
                      CHECK (status IN ('pending', 'approved', 'rejected')),
  conflict       boolean NOT NULL DEFAULT false,
  handled_by     uuid REFERENCES auth.users(id),
  handled_at     timestamptz,
  admin_note     text CHECK (admin_note IS NULL OR char_length(admin_note) <= 500),
  created_at     timestamptz NOT NULL DEFAULT now(),

  CHECK (start_time < end_time)
);
