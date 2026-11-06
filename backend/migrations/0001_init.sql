-- Strasse : schéma initial (PostgreSQL + PostGIS)
CREATE EXTENSION IF NOT EXISTS postgis;

-- Comptes facultatifs : e-mail et empreinte de mot de passe uniquement.
CREATE TABLE users (
  id            uuid PRIMARY KEY,
  email         text NOT NULL UNIQUE CHECK (email = lower(email)),
  password_hash text NOT NULL,
  created_at    timestamptz NOT NULL DEFAULT now()
);

-- Jetons de rafraîchissement : seul le hachage SHA-256 est stocké.
CREATE TABLE refresh_tokens (
  token_hash text PRIMARY KEY,
  user_id    uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  family_id  uuid NOT NULL,
  expires_at timestamptz NOT NULL,
  revoked    boolean NOT NULL DEFAULT false
);
CREATE INDEX refresh_tokens_family_idx ON refresh_tokens (family_id);
CREATE INDEX refresh_tokens_user_idx ON refresh_tokens (user_id);

-- Synchronisation : favoris, collections, voyages, préférences.
-- `data` contient le JSON de l'élément, chiffré (enc:v1:…) si SYNC_ENCRYPTION_KEY est défini.
-- Aucun historique GPS n'est jamais stocké ici.
CREATE TABLE sync_items (
  user_id    uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  kind       text NOT NULL CHECK (kind IN ('favorites','collections','trips','preferences')),
  id         text NOT NULL,
  data       text NOT NULL,
  updated_at timestamptz NOT NULL,
  deleted    boolean NOT NULL DEFAULT false,
  PRIMARY KEY (user_id, kind, id)
);
CREATE INDEX sync_items_since_idx ON sync_items (user_id, kind, updated_at);

-- Signalements communautaires, anonymes.
CREATE TABLE reports (
  id            uuid PRIMARY KEY,
  type          text NOT NULL CHECK (type IN ('accident','roadwork','slowdown','closure','obstacle','danger','other')),
  lat           double precision NOT NULL CHECK (lat BETWEEN -90 AND 90),
  lon           double precision NOT NULL CHECK (lon BETWEEN -180 AND 180),
  geom          geography(Point, 4326) NOT NULL,
  created_at    timestamptz NOT NULL,
  expires_at    timestamptz NOT NULL,
  status        text NOT NULL DEFAULT 'active' CHECK (status IN ('active','hidden','expired')),
  confirmations integer NOT NULL DEFAULT 0,
  rejections    integer NOT NULL DEFAULT 0,
  reporter_hash text NOT NULL
);
CREATE INDEX reports_geom_idx ON reports USING GIST (geom);
CREATE INDEX reports_status_expires_idx ON reports (status, expires_at);

-- Un seul vote par installation (pseudonymisée) et par signalement.
CREATE TABLE report_votes (
  report_id  uuid NOT NULL REFERENCES reports(id) ON DELETE CASCADE,
  voter_hash text NOT NULL,
  vote       text NOT NULL CHECK (vote IN ('confirm','reject')),
  created_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (report_id, voter_hash)
);
