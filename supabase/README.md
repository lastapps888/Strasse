# Strasse — backend Supabase (facultatif)

Ce dossier contient tout ce qu'il faut pour que le compte, la synchronisation et les signalements fonctionnent avec **votre propre projet Supabase**. **Rien n'est créé à votre place** : tant que vous n'avez pas fait les étapes ci-dessous, l'application reste pleinement utilisable sans compte.

## Mise en place

1. Créez un projet sur <https://supabase.com> (ou auto-hébergez Supabase).
2. Éditeur SQL → collez et exécutez `migrations/0001_strasse.sql` (rejouable sans danger).
3. Authentication → Providers → Email : activez. Choisissez si la confirmation par e-mail est exigée (recommandé). Authentication → URL configuration : renseignez votre « Site URL ».
4. Project Settings → API : copiez l'**URL du projet** et la clé **anon / publishable**. N'utilisez **jamais** la clé `service_role` dans l'application.
5. Dans l'application : Réglages → Services → « Compte et synchronisation » → Supabase → Identifiants. Ou à la compilation : `--dart-define=STRASSE_SUPABASE_URL=… --dart-define=STRASSE_SUPABASE_ANON_KEY=…`.
6. Bouton « Tester » : vérifie que le projet répond (`/auth/v1/health`). Il ne prouve pas que le SQL a été exécuté ; testez ensuite une inscription et une synchronisation.

## Sécurité

- RLS activée sur toutes les tables ; `sync_items` : chaque utilisateur ne voit et ne modifie que ses lignes.
- `reports` et `report_votes` : aucun accès direct ; tout passe par des fonctions `SECURITY DEFINER` à `search_path` fixé.
- Lecture des signalements ouverte à tous (aucune donnée personnelle renvoyée) ; création et vote réservés aux comptes, avec limites horaires.
- Suppression de compte : `delete_my_account()` supprime l'utilisateur ; les données synchronisées et les votes sont supprimés en cascade, les signalements restent mais sont anonymisés.

## Tests

`./run_tests.sh` rejoue la migration deux fois puis exécute `tests/rls_test.sql` sur une base PostgreSQL jetable (`PGURL=postgresql://user@hôte:5432`). Les tests utilisent `tests/mock_supabase.sql`, qui **imite** le schéma `auth` et les rôles `anon`/`authenticated` : ils valident la logique SQL, pas un vrai projet Supabase.

## Nettoyage planifié (facultatif)

```sql
select cron.schedule('strasse-purge', '17 3 * * *', $$select public.purge_expired_reports()$$);
```
(nécessite l'extension `pg_cron`.)

## Limites

- Plan gratuit : projet mis en pause après une semaine d'inactivité, quotas de comptes et de requêtes.
- Les e-mails de confirmation / réinitialisation utilisent le SMTP par défaut de Supabase (très limité) : configurez votre propre SMTP pour un usage réel.
- Pas de position GPS continue envoyée : seuls les signalements créés volontairement contiennent une position.
