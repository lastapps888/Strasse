-- Tests de la migration : isolation RLS, fusion, votes, expiration, suppression de compte.
\set ON_ERROR_STOP on
insert into auth.users (id, email) values
  ('11111111-1111-1111-1111-111111111111', 'a@example.org'),
  ('22222222-2222-2222-2222-222222222222', 'b@example.org');

create or replace function pg_temp.as_user(u text) returns void language plpgsql as $$
begin
  perform set_config('request.jwt.claim.sub', u, false);
  if u = '' then execute 'set role anon'; else execute 'set role authenticated'; end if;
end $$;
create or replace function pg_temp.expect_fail(q text, label text) returns void language plpgsql as $$
begin
  begin execute q; exception when others then raise notice 'OK (refusé) : % -> %', label, sqlerrm; return; end;
  raise exception 'ÉCHEC : % aurait dû être refusé', label;
end $$;
grant execute on function pg_temp.as_user(text) to public;

-- 1. Synchronisation : chaque utilisateur ne voit que ses lignes
select pg_temp.as_user('11111111-1111-1111-1111-111111111111');
insert into public.sync_items (kind, id, data, updated_at) values ('favorite', 'f1', '{"name":"Maison"}', '2026-01-02T10:00:00Z');
select pg_temp.as_user('22222222-2222-2222-2222-222222222222');
insert into public.sync_items (kind, id, data) values ('favorite', 'f1', '{"name":"Bureau"}');
do $$ begin
  if (select count(*) from public.sync_items) <> 1 then raise exception 'ÉCHEC : B voit % lignes', (select count(*) from public.sync_items); end if;
  if (select data->>'name' from public.sync_items) <> 'Bureau' then raise exception 'ÉCHEC contenu'; end if;
end $$;
select pg_temp.expect_fail($q$insert into public.sync_items (user_id, kind, id) values ('11111111-1111-1111-1111-111111111111','favorite','x')$q$, 'insertion au nom d''un autre utilisateur');
select pg_temp.expect_fail($q$insert into public.sync_items (kind, id) values ('hack','x')$q$, 'type inconnu');

-- 2. Upsert : plus récent gagne
select pg_temp.as_user('11111111-1111-1111-1111-111111111111');
insert into public.sync_items (kind, id, data, updated_at) values ('favorite', 'f1', '{"name":"Ancien"}', '2026-01-01T00:00:00Z')
  on conflict (user_id, kind, id) do update set data = excluded.data, updated_at = excluded.updated_at, deleted = excluded.deleted;
do $$ begin if (select data->>'name' from public.sync_items) <> 'Maison' then raise exception 'ÉCHEC : une écriture ancienne a écrasé la plus récente'; end if; end $$;
insert into public.sync_items (kind, id, data, updated_at) values ('favorite', 'f1', '{"name":"Nouveau"}', '2026-01-03T00:00:00Z')
  on conflict (user_id, kind, id) do update set data = excluded.data, updated_at = excluded.updated_at, deleted = excluded.deleted;
do $$ begin if (select data->>'name' from public.sync_items) <> 'Nouveau' then raise exception 'ÉCHEC : écriture récente ignorée'; end if; end $$;

-- 3. Anonyme : aucun accès aux tables
select pg_temp.as_user('');
select pg_temp.expect_fail('select * from public.sync_items', 'lecture sync_items par anon');
select pg_temp.expect_fail('select * from public.reports', 'lecture directe de reports par anon');
select pg_temp.expect_fail($q$select public.create_report('accident', 48.85, 2.35)$q$, 'création par anon');
select pg_temp.expect_fail('select public.delete_my_account()', 'suppression de compte par anon');

-- 4. Signalements
select pg_temp.as_user('11111111-1111-1111-1111-111111111111');
select pg_temp.expect_fail($q$select public.create_report('inconnu', 48.85, 2.35)$q$, 'type invalide');
select pg_temp.expect_fail($q$select public.create_report('accident', 95, 2.35)$q$, 'latitude invalide');
create temp table t1 as select public.create_report('accident', 48.8566, 2.3522) as r;
grant all on t1 to public;
do $$ declare j jsonb := (select r from t1); begin
  if (j->>'merged')::boolean then raise exception 'ÉCHEC : premier signalement fusionné'; end if;
  if (j->>'confirmations')::int <> 1 then raise exception 'ÉCHEC confirmations'; end if;
  if (j->>'reliability')::float not between 0.02 and 0.98 then raise exception 'ÉCHEC fiabilité'; end if;
end $$;

-- B confirme un signalement proche (à ~60 m) : fusion
select pg_temp.as_user('22222222-2222-2222-2222-222222222222');
create temp table t2 as select public.create_report('accident', 48.8570, 2.3526) as r;
do $$ declare j jsonb := (select r from t2); begin
  if not (j->>'merged')::boolean then raise exception 'ÉCHEC : signalement proche non fusionné'; end if;
  if (j->>'confirmations')::int <> 2 then raise exception 'ÉCHEC : confirmations = %', j->>'confirmations'; end if;
end $$;
-- Un type différent au même endroit n'est pas fusionné
do $$ declare j jsonb := public.create_report('roadwork', 48.8570, 2.3526); begin
  if (j->>'merged')::boolean then raise exception 'ÉCHEC : fusion entre types différents'; end if;
end $$;
-- Un revote remplace le vote, sans doublon
do $$ declare id uuid := ((select r from t1)->>'id')::uuid; j jsonb; begin
  j := public.vote_report(id, false);
  if (j->>'confirmations')::int <> 1 or (j->>'rejections')::int <> 1 then raise exception 'ÉCHEC revote : %', j; end if;
  j := public.vote_report(id, false);
  if (j->>'rejections')::int <> 1 then raise exception 'ÉCHEC : double vote'; end if;
end $$;
-- Lecture publique par bbox
select pg_temp.as_user('');
do $$ declare n int; begin
  select count(*) into n from public.reports_in_bbox(2.30, 48.80, 2.40, 48.90);
  if n <> 2 then raise exception 'ÉCHEC bbox : % signalements au lieu de 2', n; end if;
  select count(*) into n from public.reports_in_bbox(10, 10, 10.1, 10.1);
  if n <> 0 then raise exception 'ÉCHEC bbox vide'; end if;
  select count(*) into n from public.reports_in_bbox(-10, -10, 20, 20);
  if n <> 0 then raise exception 'ÉCHEC : zone trop grande acceptée'; end if;
end $$;
select pg_temp.expect_fail($q$select public.vote_report(gen_random_uuid(), true)$q$, 'vote par anon');

-- 5. Masquage automatique : rejets >= confirmations + 3
reset role;
insert into auth.users (id) select gen_random_uuid() from generate_series(1,3);
do $$ declare rid uuid; u record; begin
  select ((select r from t1)->>'id')::uuid into rid;
  for u in select id from auth.users where email is null limit 3 loop
    perform set_config('request.jwt.claim.sub', u.id::text, false);
    perform public.vote_report(rid, false);
  end loop;
  perform set_config('request.jwt.claim.sub', '', false);
  if (select status from public.reports where id = rid) <> 'hidden' then
    raise exception 'ÉCHEC : non masqué (conf=%, rej=%)', (select confirmations from public.reports where id = rid), (select rejections from public.reports where id = rid);
  end if;
end $$;

-- 6. Expiration
update public.reports set expires_at = now() - interval '1 minute' where type = 'roadwork';
select pg_temp.as_user('');
do $$ begin
  if exists (select 1 from public.reports_in_bbox(2.30, 48.80, 2.40, 48.90) j where j->>'type' = 'roadwork') then
    raise exception 'ÉCHEC : signalement expiré encore visible';
  end if;
end $$;

-- 7. Suppression du compte : données supprimées, signalements anonymisés
select pg_temp.as_user('11111111-1111-1111-1111-111111111111');
select public.delete_my_account();
reset role;
do $$ begin
  if exists (select 1 from auth.users where id = '11111111-1111-1111-1111-111111111111') then raise exception 'ÉCHEC : utilisateur non supprimé'; end if;
  if exists (select 1 from public.sync_items where user_id = '11111111-1111-1111-1111-111111111111') then raise exception 'ÉCHEC : données non supprimées'; end if;
  if exists (select 1 from public.reports where created_by = '11111111-1111-1111-1111-111111111111') then raise exception 'ÉCHEC : signalements non anonymisés'; end if;
  if not exists (select 1 from public.sync_items where user_id = '22222222-2222-2222-2222-222222222222') then raise exception 'ÉCHEC : données de B supprimées'; end if;
end $$;
\echo TOUS LES TESTS SQL PASSENT
