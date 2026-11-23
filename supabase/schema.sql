-- Atelier 6 — File d'attente résiliente
-- À exécuter dans le SQL Editor du projet Supabase.

create extension if not exists pgcrypto;

create table if not exists public.clients (
  id uuid primary key default gen_random_uuid(),
  name text not null check (char_length(trim(name)) > 0),
  lat double precision,
  lng double precision,
  location_accuracy_m double precision,
  location_captured_at timestamptz,
  created_at timestamptz not null default now(),
  constraint valid_latitude check (lat is null or lat between -90 and 90),
  constraint valid_longitude check (lng is null or lng between -180 and 180)
);

-- Pagination : la file est affichée du plus récent au plus ancien.
create index if not exists clients_created_at_idx
  on public.clients (created_at desc, id desc);

alter table public.clients enable row level security;

drop policy if exists "clients are readable" on public.clients;
create policy "clients are readable"
  on public.clients for select
  to anon, authenticated
  using (true);

drop policy if exists "anyone can join the queue" on public.clients;
create policy "anyone can join the queue"
  on public.clients for insert
  to anon, authenticated
  with check (true);

-- Nécessaire pour le fallback upsert du repository.
drop policy if exists "anyone can update the queue" on public.clients;
create policy "anyone can update the queue"
  on public.clients for update
  to anon, authenticated
  using (true)
  with check (true);

drop policy if exists "anyone can leave the queue" on public.clients;
create policy "anyone can leave the queue"
  on public.clients for delete
  to anon, authenticated
  using (true);

-- Inscription atomique et idempotente : le même id ne crée jamais de doublon.
create or replace function public.register_queue_client(
  p_id uuid,
  p_name text,
  p_lat double precision,
  p_lng double precision,
  p_accuracy double precision,
  p_created_at timestamptz
)
returns setof public.clients
language plpgsql
security definer
set search_path = public
as $$
begin
  return query
  insert into public.clients (id, name, lat, lng, location_accuracy_m, created_at)
  values (p_id, trim(p_name), p_lat, p_lng, p_accuracy, p_created_at)
  on conflict (id) do update
    set name = excluded.name,
        lat = excluded.lat,
        lng = excluded.lng,
        location_accuracy_m = excluded.location_accuracy_m
  returning *;
end;
$$;

revoke all on function public.register_queue_client(
  uuid, text, double precision, double precision, double precision, timestamptz
) from public;

grant execute on function public.register_queue_client(
  uuid, text, double precision, double precision, double precision, timestamptz
) to anon, authenticated;

-- Realtime : indispensable pour la fusion des inserts sans doublon.
do $$
begin
  execute 'alter publication supabase_realtime add table public.clients';
exception
  when duplicate_object then null;
end $$;
