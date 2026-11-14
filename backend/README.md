# Backend Strasse

API indépendante et modulaire de Strasse (Node 22, TypeScript strict, Fastify 5, PostgreSQL + PostGIS, Redis facultatif).
Aucun compte n'est requis pour utiliser l'application : cette API ne sert qu'à la **synchronisation facultative**,
aux **signalements communautaires anonymes** et au **trafic externe**. L'historique GPS n'est jamais accepté ni stocké.

## Prérequis

- Node 22 ou plus récent
- PostgreSQL 14+ avec l'extension PostGIS (pour la production) ; Redis 6+ (facultatif)

## Lancement local

```bash
cd backend
cp .env.example .env        # puis adapter
npm install
npm run dev                  # sans DATABASE_URL : stockage en mémoire (développement uniquement)
```

Avec une base PostgreSQL : renseigner `DATABASE_URL`, puis `npm run migrate` avant `npm run dev`.

## Docker

```bash
cp .env.example .env        # définir POSTGRES_PASSWORD, JWT_SECRET, SERVER_SALT (32 car. min.)
docker compose up --build   # base PostGIS + Redis + API sur le port 8080 ; migrations au démarrage
```

## Commandes

| Commande | Effet |
|---|---|
| `npm run typecheck` | Vérification des types (`tsc --noEmit`) |
| `npm test` | Tests (`node:test`, dépôts en mémoire, `app.inject`) |
| `npm run build` | Compilation vers `dist/` |
| `npm run migrate` | Applique les migrations SQL de `migrations/` |

## Variables d'environnement

Voir `.env.example` (toutes documentées). En production (`NODE_ENV=production`), `JWT_SECRET`, `SERVER_SALT`
(32 caractères minimum) et `DATABASE_URL` sont obligatoires, sinon le serveur refuse de démarrer.

## Contrat d'API

Résumé ; la spécification complète est dans `documentation/API.md` (à la racine : `API.md`).

- `GET /v1/health`
- `POST /v1/auth/register | login | refresh | logout`, `DELETE /v1/account`
- `GET /v1/sync/pull`, `POST /v1/sync/push` (dernière écriture gagnante, suppressions propagées)
- `GET /v1/reports?bbox=`, `POST /v1/reports`, `POST /v1/reports/:id/confirm | reject` (en-tête `X-Install-Id`)
- `GET /v1/traffic/incidents?bbox=` (`available:false` sans fournisseur : jamais de données inventées)
- `GET /v1/admin/reports`, `POST /v1/admin/reports/:id/moderate` (uniquement si `ADMIN_TOKEN` est défini)

Erreurs : `{"error":{"code":"snake_case","message":"message en français"}}`.

## Vie privée

- Journaux anonymisés : pas d'adresse IP, pas d'en-têtes d'identification, pas de paramètres de requête.
- Signalements : seul un pseudonyme `HMAC-SHA256(X-Install-Id, SERVER_SALT)` est conservé, pour limiter les abus et
  empêcher les votes multiples. Il n'est jamais renvoyé par l'API.
- Synchronisation : chiffrement AES-256-GCM des éléments au repos si `SYNC_ENCRYPTION_KEY` est défini.
- Suppression du compte : supprime le compte, les sessions et toutes les données synchronisées.

## Limites connues et ce qui n'est PAS vérifié

Ce backend a été écrit dans un environnement **sans accès au registre npm, sans PostgreSQL ni Redis**.
En conséquence, à la date de livraison :

- **Aucune dépendance n'a été installée et ni `tsc` ni `npm test` n'ont été exécutés.** Les tests sont écrits mais
  non lancés : il faut exécuter `npm install && npm run typecheck && npm test` et corriger d'éventuelles erreurs.
- Les dépôts PostgreSQL/PostGIS (`src/repositories/postgres`), le runner de migrations, le client Redis
  et le connecteur TomTom n'ont **jamais été exécutés** contre de vrais services.
- Le comportement de `@fastify/rate-limit` avec `errorResponseBuilder` retournant une `Error` est à confirmer par les tests.
- Les votes ne sont pas atomiques côté PostgreSQL (lecture puis écriture) : en forte concurrence, un compteur peut
  être légèrement sous-estimé. À remplacer par des `UPDATE … SET confirmations = confirmations + 1` si besoin.
- TomTom : vérifier les conditions de licence et de redistribution avant la production.
