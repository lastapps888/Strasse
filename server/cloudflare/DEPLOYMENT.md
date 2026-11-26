# Déployer le serveur Cloudflare Strasse

Le Worker reçoit les retours envoyés depuis l'écran « Envoyer un retour » et les relaie par Resend. Le serveur utilise également D1 pour la limitation de fréquence et les fonctions de compte, synchronisation et signalements.

## 1. Créer la base D1

Depuis ce dossier :

```bash
npm install
npx wrangler login
npx wrangler d1 create strasse
```

Copiez l'identifiant D1 renvoyé par Wrangler dans `wrangler.toml`, à la place de `REMPLACER_PAR_L_ID_D1`. Conservez exactement le nom de base `strasse` et le binding `DB`.

Initialisez ensuite le schéma distant :

```bash
npm run db:init
```

## 2. Configurer Resend

Vérifiez d'abord le domaine expéditeur dans Resend. Puis enregistrez les trois valeurs comme secrets Cloudflare (ne les écrivez jamais dans Git, dans `config/env.json` ou dans l'application) :

```bash
npx wrangler secret put RESEND_API_KEY
npx wrangler secret put FEEDBACK_TO
npx wrangler secret put FEEDBACK_FROM
```

- `RESEND_API_KEY` : clé API Resend.
- `FEEDBACK_TO` : adresse qui reçoit les retours.
- `FEEDBACK_FROM` : expéditeur du domaine vérifié, par exemple `Strasse <retours@votre-domaine.fr>`.

## 3. Déployer et vérifier

```bash
npm run deploy
curl https://strasse-server.lastapps888.workers.dev/v1/health
```

La réponse attendue de la route de santé est `{"ok":true}`. Faites ensuite un envoi réel depuis Strasse : l'interface ne confirme l'envoi que si Resend accepte le message. Un Worker avec secrets absents renvoie volontairement une erreur explicite et ne prétend pas que le mail est parti.

## 4. Configurer les builds Strasse

L'URL du Worker est déjà définie par défaut dans `AppConfig.strasseServerUrl`. Si vous déployez sur une autre adresse, fournissez `STRASSE_API_URL` dans l'environnement du build.

Les tests automatisés utilisent une base D1 SQLite temporaire et simulent l'acceptation de Resend ; ils ne peuvent ni créer votre base Cloudflare, ni vérifier votre domaine expéditeur, ni envoyer un e-mail réel à votre destinataire.