# Configuration de l'envoi des retours

Strasse envoie les retours via le Worker Cloudflare, qui relaie le message au fournisseur Resend. L'application ne contient ni l'adresse destinataire du projet ni la clé API Resend.

## Prérequis

- Un compte Resend avec un domaine expéditeur vérifié.
- Le Worker Strasse déployé avec son binding D1 `DB`.
- Les identifiants e-mail ajoutés exclusivement comme secrets Cloudflare.

## Secrets du Worker

Depuis `server/cloudflare`, exécuter les trois commandes suivantes et saisir les valeurs dans l'invite :

```bash
npx wrangler secret put RESEND_API_KEY
npx wrangler secret put FEEDBACK_TO
npx wrangler secret put FEEDBACK_FROM
```

- `RESEND_API_KEY` : clé Resend limitée à l'envoi.
- `FEEDBACK_TO` : adresse de réception du projet.
- `FEEDBACK_FROM` : nom et adresse d'expédition utilisant le domaine vérifié dans Resend, par exemple `Strasse <notifications@domaine-verifie.fr>`.

Ne pas placer ces valeurs dans `wrangler.toml`, dans les fichiers Dart, dans GitHub Actions ou dans les paramètres de l'application.

## Première configuration D1

Depuis le dossier `server/cloudflare`, authentifier Wrangler puis créer la base D1 en Europe :

```bash
npx wrangler login
npx wrangler d1 create strasse --location weur
```

La commande retourne un identifiant unique. Remplacer uniquement la valeur `REMPLACER_PAR_L_ID_D1` de `wrangler.toml` par cet identifiant. Ne pas inventer ni réutiliser l'identifiant d'une autre base. Vérifier que le bloc conserve bien `binding = "DB"` et `database_name = "strasse"`.

Initialiser la base distante avec le schéma versionné du dépôt :

```bash
npx wrangler d1 execute strasse --remote --file=./schema.sql
```

Cette opération crée les tables de comptes, sessions, données chiffrées, signalements, votes et limites de fréquence. Ne pas lancer le schéma sur une base de production contenant déjà des données sans avoir préalablement vérifié sa compatibilité.

## Déploiement et vérification

Après avoir configuré le binding D1 et les trois secrets, déployer le Worker avec :

```bash
npx wrangler deploy
```

Vérifier que le Worker répond :

```bash
curl -fsS https://strasse-server.lastapps888.workers.dev/v1/health
```

Le point d'entrée utilisé par l'application est `POST /v1/feedback`. Le Worker applique une limite de fréquence, valide le message et l'adresse de réponse, puis appelle `POST https://api.resend.com/emails`. Il retourne `success: true` uniquement si Resend retourne une réponse HTTP positive contenant un identifiant d'e-mail.

Un accusé positif signifie que Resend a accepté la demande d'envoi ; il ne prouve pas à lui seul l'arrivée dans la boîte de réception. Après le déploiement, faire un vrai envoi depuis l'application vers une boîte de test et vérifier la réception ainsi que les journaux de livraison Resend.
