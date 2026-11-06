# API du backend Strasse (facultatif)

Base : `STRASSE_API_URL`, préfixe `/v1`. Erreurs : `{ "error": { "code": "...", "message": "..." } }` (messages en français).

| Méthode et chemin | Auth | Description |
|---|---|---|
| `GET /v1/health` | – | `{status, version, time}` |
| `POST /v1/auth/register` | – | `{email, password(≥10)}` → jetons |
| `POST /v1/auth/login` | – | idem |
| `POST /v1/auth/refresh` | – | `{refreshToken}` → nouveaux jetons (rotation) |
| `POST /v1/auth/logout` | Bearer | `{refreshToken}` |
| `DELETE /v1/account` | Bearer | Supprime le compte et ses données |
| `GET /v1/sync/pull?since=ISO` | Bearer | Éléments modifiés depuis la date |
| `POST /v1/sync/push` | Bearer | `{favorites[], collections[], trips[], preferences?}` ; éléments `{id(uuid), updatedAt, deleted, data}`, dernière écriture gagne |
| `GET /v1/reports?bbox=s,w,n,e` | – | Signalements actifs |
| `POST /v1/reports` | en-tête `X-Install-Id` (UUID) | `{type, lat, lon}` ; un doublon proche vaut confirmation |
| `POST /v1/reports/:id/confirm`, `/reject` | `X-Install-Id` | Un vote par installation |
| `GET /v1/traffic/incidents?bbox=…` | – | `{available, provider, incidents[], fetchedAt}` ; `available:false` si aucun fournisseur |
| `GET /v1/admin/reports?status=` | `Authorization: Bearer ADMIN_TOKEN` | Modération (absent si `ADMIN_TOKEN` vide) |
| `POST /v1/admin/reports/:id/moderate` | idem | `{action: hide|restore|delete}` |

Types de signalement : voir `backend/src/services/expiry.ts`. Les données de synchronisation sont chiffrées au repos si `SYNC_ENCRYPTION_KEY` est défini ; l'identifiant d'installation n'est jamais stocké en clair.
