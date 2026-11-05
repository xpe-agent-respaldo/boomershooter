-- Boomer Shooter: perfiles, salas y resultados.
-- Ejecutar en Supabase SQL Editor. Nunca pongas claves en este archivo.

create extension if not exists "pgcrypto";

create table if not exists public.player_profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  display_name text not null check (char_length(display_name) between 2 and 24),
  platform text not null default 'unknown' check (platform in ('windows', 'linux', 'web', 'unknown')),
  controller_connected boolean not null default false,
  total_kills integer not null default 0 check (total_kills >= 0),
  total_waves integer not null default 0 check (total_waves >= 0),
  games_played integer not null default 0 check (games_played >= 0),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.wave_matches (
  id uuid primary key default gen_random_uuid(),
  nakama_match_id text unique,
  host_user_id uuid references auth.users(id) on delete set null,
  visibility text not null default 'public' check (visibility in ('public', 'private')),
  room_code text unique,
  map_id text not null default 'recycling_plant',
  wave_reached integer not null default 0 check (wave_reached >= 0),
  player_count integer not null default 0 check (player_count between 0 and 4),
  status text not null default 'lobby' check (status in ('lobby', 'active', 'finished', 'closed')),
  started_at timestamptz,
  finished_at timestamptz,
  created_at timestamptz not null default now()
);

create table if not exists public.wave_match_players (
  match_id uuid not null references public.wave_matches(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  kills integer not null default 0 check (kills >= 0),
  revives integer not null default 0 check (revives >= 0),
  waves_survived integer not null default 0 check (waves_survived >= 0),
  joined_at timestamptz not null default now(),
  primary key (match_id, user_id)
);

alter table public.player_profiles enable row level security;
alter table public.wave_matches enable row level security;
alter table public.wave_match_players enable row level security;

drop policy if exists "profiles are publicly readable" on public.player_profiles;
create policy "profiles are publicly readable" on public.player_profiles for select using (true);
drop policy if exists "players manage own profile" on public.player_profiles;
create policy "players manage own profile" on public.player_profiles for all using (auth.uid() = id) with check (auth.uid() = id);

drop policy if exists "public lobbies are readable" on public.wave_matches;
create policy "public lobbies are readable" on public.wave_matches for select using (visibility = 'public' or host_user_id = auth.uid());
drop policy if exists "players create lobbies" on public.wave_matches;
create policy "players create lobbies" on public.wave_matches for insert with check (auth.uid() = host_user_id);
drop policy if exists "hosts update lobbies" on public.wave_matches;
create policy "hosts update lobbies" on public.wave_matches for update using (auth.uid() = host_user_id) with check (auth.uid() = host_user_id);

drop policy if exists "players read match members" on public.wave_match_players;
create policy "players read match members" on public.wave_match_players for select using (
  exists (select 1 from public.wave_matches m where m.id = match_id and (m.visibility = 'public' or m.host_user_id = auth.uid()))
);
drop policy if exists "players join matches" on public.wave_match_players;
create policy "players join matches" on public.wave_match_players for insert with check (auth.uid() = user_id);
drop policy if exists "players update own result" on public.wave_match_players;
create policy "players update own result" on public.wave_match_players for update using (auth.uid() = user_id) with check (auth.uid() = user_id);

create index if not exists wave_matches_lobby_idx on public.wave_matches(status, visibility, created_at desc);
create index if not exists wave_match_players_user_idx on public.wave_match_players(user_id, joined_at desc);
