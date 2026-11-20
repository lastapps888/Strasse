-- Base D1 (SQLite) du serveur Strasse hébergé. Le serveur ne contient AUCUNE donnée lisible de l'utilisateur :
--  * l'identifiant de compte est un condensé SHA-256 de l'e-mail (calculé par l'application) ;
--  * le « mot de passe » reçu est une clé dérivée (Argon2id) côté appareil, jamais le mot de passe lui-même ;
--  * les favoris, collections, trajets et préférences sont des blocs chiffrés de bout en bout (AES-256-GCM).
CREATE TABLE IF NOT EXISTS accounts (
  email_id TEXT PRIMARY KEY,
  auth_salt TEXT NOT NULL,
  auth_hash TEXT NOT NULL,
  wrapped_mk TEXT NOT NULL,
  wrapped_mk_rec TEXT NOT NULL,
  recovery_salt TEXT NOT NULL,
  recovery_hash TEXT NOT NULL,
  created_at INTEGER NOT NULL
);
CREATE TABLE IF NOT EXISTS sessions (
  token_hash TEXT PRIMARY KEY,
  email_id TEXT NOT NULL,
  expires_at INTEGER NOT NULL
);
CREATE INDEX IF NOT EXISTS sessions_email ON sessions(email_id);
CREATE TABLE IF NOT EXISTS items (
  email_id TEXT NOT NULL,
  kind TEXT NOT NULL,
  id TEXT NOT NULL,
  updated_at INTEGER NOT NULL,
  deleted INTEGER NOT NULL DEFAULT 0,
  blob TEXT,
  PRIMARY KEY (email_id, kind, id)
);
CREATE INDEX IF NOT EXISTS items_since ON items(email_id, updated_at);
-- Signalements communautaires : publics par nature (type + position arrondie + durée de vie), sans lien avec un compte.
CREATE TABLE IF NOT EXISTS reports (
  id TEXT PRIMARY KEY,
  type TEXT NOT NULL,
  lat REAL NOT NULL,
  lon REAL NOT NULL,
  created_at INTEGER NOT NULL,
  expires_at INTEGER NOT NULL,
  confirms INTEGER NOT NULL DEFAULT 1,
  rejects INTEGER NOT NULL DEFAULT 0
);
CREATE INDEX IF NOT EXISTS reports_geo ON reports(lat, lon);
CREATE TABLE IF NOT EXISTS report_votes (
  report_id TEXT NOT NULL,
  voter TEXT NOT NULL,
  PRIMARY KEY (report_id, voter)
);
CREATE TABLE IF NOT EXISTS rate (
  k TEXT PRIMARY KEY,
  n INTEGER NOT NULL,
  window_start INTEGER NOT NULL
);
