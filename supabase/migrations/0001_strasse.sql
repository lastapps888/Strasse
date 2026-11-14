-- Strasse — schéma Supabase (compte, synchronisation, signalements communautaires).
-- À exécuter une seule fois dans l'éditeur SQL de votre projet Supabase (ou via `supabase db push`).
-- Sécurité : RLS activée partout ; l'application n'utilise que la clé publique « anon ».
-- Les fonctions SECURITY DEFINER fixent leur search_path et ne font confiance qu'à auth.uid().

-- ------------------------------------------------------------------ Synchronisation
create table if not exists public.sync_items (
  user_id    uuid        not null default auth.uid() references auth.users (id) on delete cascade,
  kind       text        not null check (kind in ('favorite', 'collection', 'trip', 'preferences')),
  id         text        not null check (char_length(id) between 1 and 80),
  data       jsonb       not null default '{}'::jsonb check (pg_column_size(data) < 65536),
  updated_at timestamptz not null default now(),
  deleted    boolean     not null default false,
  primary key (user_id, kind, id)
);

create index if not exists sync_items_user_updated_idx on public.sync_items (user_id, updated_at);

alter table public.sync_items enable row level security;

drop policy if exists sync_items_select_own on public.sync_items;
drop policy if exists sync_items_insert_own on public.sync_items;
drop policy if exists sync_items_update_own on public.sync_items;
drop policy if exists sync_items_delete_own on public.sync_items;

create policy sync_items_select_own on public.sync_items for select to authenticated
  using (user_id = (select auth.uid()));
create policy sync_items_insert_own on public.sync_items for insert to authenticated
  with check (user_id = (select auth.uid()));
create policy sync_items_update_own on public.sync_items for update to authenticated
  using (user_id = (select auth.uid())) with check (user_id = (select auth.uid()));
create policy sync_items_delete_own on public.sync_items for delete to authenticated
  using (user_id = (select auth.uid()));

-- Le plus récent gagne : une écriture plus ancienne que la ligne existante est ignorée.
create or replace function public.sync_items_keep_newest()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  if new.updated_at < old.updated_at then
    return null;
  end if;
  return new;
end;
$$;

drop trigger if exists sync_items_keep_newest on public.sync_items;
create trigger sync_items_keep_newest before update on public.sync_items
  for each row execute function public.sync_items_keep_newest();

-- Heure du serveur : évite de dépendre de l'horloge de l'appareil pour la synchronisation incrémentale.
create or replace function public.server_time()
returns timestamptz
language sql
stable
set search_path = public
as $$ select now(); $$;

-- ------------------------------------------------------------------ Signalements
create table if not exists public.reports (
  id            uuid             primary key default gen_random_uuid(),
  type          text             not null check (type in ('accident', 'roadwork', 'slowdown', 'closure', 'obstacle', 'danger', 'other')),
  lat           double precision not null check (lat between -90 and 90),
  lon           double precision not null check (lon between -180 and 180),
  created_by    uuid             references auth.users (id) on delete set null,
  created_at    timestamptz      not null default now(),
  expires_at    timestamptz      not null,
  status        text             not null default 'active' check (status in ('active', 'hidden')),
  confirmations integer          not null default 1 check (confirmations >= 0),
  rejections    integer          not null default 0 check (rejections >= 0)
);

create index if not exists reports_active_idx on public.reports (lat, lon) where status = 'active';
create index if not exists reports_expires_idx on public.reports (expires_at);

create table if not exists public.report_votes (
  report_id  uuid        not null references public.reports (id) on delete cascade,
  user_id    uuid        not null references auth.users (id) on delete cascade,
  vote       smallint    not null check (vote in (1, -1)),
  created_at timestamptz not null default now(),
  primary key (report_id, user_id)
);

-- Aucune politique d'écriture ni de lecture directe : tout passe par les fonctions ci-dessous.
alter table public.reports enable row level security;
alter table public.report_votes enable row level security;

revoke all on public.reports from anon, authenticated;
revoke all on public.report_votes from anon, authenticated;

-- Durée de validité de base par type (miroir du serveur Strasse).
create or replace function public.report_base_minutes(p_type text)
returns integer
language sql
immutable
set search_path = public
as $$
  select case p_type
    when 'accident' then 120
    when 'roadwork' then 1440
    when 'slowdown' then 45
    when 'closure'  then 360
    else 60
  end;
$$;

-- Fiabilité estimée entre 0,02 et 0,98 (jamais une certitude), même modèle que le serveur Strasse.
create or replace function public.report_reliability(
  p_created timestamptz, p_expires timestamptz, p_conf integer, p_rej integer
) returns double precision
language sql
stable
set search_path = public
as $$
  with f as (
    select least(1.0, greatest(0.0,
      extract(epoch from (p_expires - now())) / greatest(1.0, extract(epoch from (p_expires - p_created)))
    )) as fresh
  ), l as (
    select -0.2 + 0.6 * greatest(0, p_conf) - 0.8 * greatest(0, p_rej) + (fresh - 0.5) as logit from f
  )
  select least(0.98, greatest(0.02, 1.0 / (1.0 + exp(-logit)))) from l;
$$;

create or replace function public.report_json(r public.reports)
returns jsonb
language sql
stable
set search_path = public
as $$
  select jsonb_build_object(
    'id', r.id,
    'type', r.type,
    'lat', r.lat,
    'lon', r.lon,
    'createdAt', r.created_at,
    'expiresAt', r.expires_at,
    'status', case when r.status = 'active' and r.expires_at <= now() then 'expired' else r.status end,
    'confirmations', r.confirmations,
    'rejections', r.rejections,
    'reliability', public.report_reliability(r.created_at, r.expires_at, r.confirmations, r.rejections)
  );
$$;

-- Lecture publique (anon et connecté) des signalements actifs d'une zone. Aucune donnée personnelle n'est renvoyée.
create or replace function public.reports_in_bbox(p_west double precision, p_south double precision, p_east double precision, p_north double precision)
returns setof jsonb
language sql
stable
security definer
set search_path = public
as $$
  select public.report_json(r)
  from public.reports r
  where r.status = 'active'
    and r.expires_at > now()
    and r.lat between least(p_south, p_north) and greatest(p_south, p_north)
    and r.lon between least(p_west, p_east) and greatest(p_west, p_east)
    and (greatest(p_south, p_north) - least(p_south, p_north)) <= 2
    and (greatest(p_west, p_east) - least(p_west, p_east)) <= 2
  order by r.created_at desc
  limit 300;
$$;

-- Création : réservée aux comptes connectés, limitée à 20 par heure. Fusionne avec un signalement actif du même
-- type à moins de 150 m (compté comme confirmation).
create or replace function public.create_report(p_type text, p_lat double precision, p_lon double precision)
returns jsonb
language plpgsql
volatile
security definer
set search_path = public
as $$
declare
  uid uuid := auth.uid();
  existing public.reports;
  created public.reports;
  base interval;
  dlat double precision := 0.00135;  -- ~150 m en latitude
  dlon double precision;
  result jsonb;
begin
  if uid is null then
    raise exception 'Connexion requise' using errcode = '42501';
  end if;
  if p_type not in ('accident', 'roadwork', 'slowdown', 'closure', 'obstacle', 'danger', 'other') then
    raise exception 'Type de signalement invalide' using errcode = '22023';
  end if;
  if p_lat is null or p_lon is null or p_lat not between -90 and 90 or p_lon not between -180 and 180 then
    raise exception 'Position invalide' using errcode = '22023';
  end if;
  if (select count(*) from public.reports where created_by = uid and created_at > now() - interval '1 hour') >= 20 then
    raise exception 'Trop de signalements : réessayez plus tard' using errcode = '54000';
  end if;

  dlon := dlat / greatest(0.01, cos(radians(p_lat)));
  select * into existing
  from public.reports r
  where r.type = p_type and r.status = 'active' and r.expires_at > now()
    and r.lat between p_lat - dlat and p_lat + dlat
    and r.lon between p_lon - dlon and p_lon + dlon
    and 6371000 * 2 * asin(sqrt(
          power(sin(radians(r.lat - p_lat) / 2), 2) +
          cos(radians(p_lat)) * cos(radians(r.lat)) * power(sin(radians(r.lon - p_lon) / 2), 2)
        )) <= 150
  order by r.created_at desc
  limit 1;

  if found then
    return public.vote_report(existing.id, true) || jsonb_build_object('merged', true);
  end if;

  base := make_interval(mins => public.report_base_minutes(p_type));
  insert into public.reports (type, lat, lon, created_by, expires_at)
  values (p_type, round(p_lat::numeric, 5), round(p_lon::numeric, 5), uid, now() + base * 1.25)
  returning * into created;
  insert into public.report_votes (report_id, user_id, vote) values (created.id, uid, 1);
  result := public.report_json(created) || jsonb_build_object('merged', false);
  return result;
end;
$$;

-- Vote : un seul par compte et par signalement (modifiable). Chaque confirmation prolonge la validité de 25 % de la
-- durée de base (plafond 3×) ; le signalement est masqué lorsque rejets >= confirmations + 3.
create or replace function public.vote_report(p_id uuid, p_confirm boolean)
returns jsonb
language plpgsql
volatile
security definer
set search_path = public
as $$
declare
  uid uuid := auth.uid();
  r public.reports;
  v smallint := case when p_confirm then 1 else -1 end;
  factor double precision;
  base_min integer;
begin
  if uid is null then
    raise exception 'Connexion requise' using errcode = '42501';
  end if;
  if (select count(*) from public.report_votes where user_id = uid and created_at > now() - interval '1 hour') >= 120 then
    raise exception 'Trop de votes : réessayez plus tard' using errcode = '54000';
  end if;
  select * into r from public.reports where id = p_id for update;
  if not found or r.status <> 'active' or r.expires_at <= now() then
    raise exception 'Signalement introuvable ou expiré' using errcode = 'P0002';
  end if;

  insert into public.report_votes (report_id, user_id, vote) values (p_id, uid, v)
  on conflict (report_id, user_id) do update set vote = excluded.vote, created_at = now();

  update public.reports x
  set confirmations = (select count(*) from public.report_votes where report_id = p_id and vote = 1),
      rejections    = (select count(*) from public.report_votes where report_id = p_id and vote = -1)
  where x.id = p_id
  returning * into r;

  base_min := public.report_base_minutes(r.type);
  factor := least(3.0, 1.0 + 0.25 * r.confirmations);
  update public.reports x
  set expires_at = r.created_at + make_interval(secs => base_min * 60 * factor),
      status = case when r.rejections >= r.confirmations + 3 then 'hidden' else r.status end
  where x.id = p_id
  returning * into r;

  return public.report_json(r);
end;
$$;

-- Suppression complète du compte et de ses données (RGPD). Les signalements restent mais deviennent anonymes.
create or replace function public.delete_my_account()
returns void
language plpgsql
volatile
security definer
set search_path = public, auth
as $$
declare
  uid uuid := auth.uid();
begin
  if uid is null then
    raise exception 'Connexion requise' using errcode = '42501';
  end if;
  delete from auth.users where id = uid;  -- cascade : sync_items et report_votes ; reports.created_by passe à NULL
end;
$$;

-- Nettoyage périodique (facultatif, à planifier avec pg_cron — voir supabase/README.md).
create or replace function public.purge_expired_reports()
returns integer
language sql
volatile
security definer
set search_path = public
as $$
  with d as (delete from public.reports where expires_at < now() - interval '7 days' returning 1)
  select count(*)::integer from d;
$$;

-- ------------------------------------------------------------------ Droits d'exécution
revoke all on function public.create_report(text, double precision, double precision) from public, anon;
revoke all on function public.vote_report(uuid, boolean) from public, anon;
revoke all on function public.delete_my_account() from public, anon;
revoke all on function public.purge_expired_reports() from public, anon, authenticated;
revoke all on function public.report_json(public.reports) from public, anon, authenticated;
revoke all on function public.report_reliability(timestamptz, timestamptz, integer, integer) from public, anon, authenticated;

grant execute on function public.create_report(text, double precision, double precision) to authenticated;
grant execute on function public.vote_report(uuid, boolean) to authenticated;
grant execute on function public.delete_my_account() to authenticated;
grant execute on function public.reports_in_bbox(double precision, double precision, double precision, double precision) to anon, authenticated;
grant execute on function public.server_time() to anon, authenticated;

grant select, insert, update, delete on public.sync_items to authenticated;
