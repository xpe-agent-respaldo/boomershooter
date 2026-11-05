-- Boomer Shooter: logros, estadisticas acumuladas y capacidad de salas.
-- Ejecutar en Supabase SQL Editor DESPUES de 001, 002 y 003. Nunca pongas claves aqui.
--
-- Principio: los resultados (kills, logros, rankings) los escribe SOLO el servidor
-- (service_role). Los jugadores solo leen. En 001 cada jugador podia actualizar su propia
-- fila de wave_match_players, lo que permitia ponerse kills falsas; aqui se cierra eso.

-- 1) Capacidad de sala: el limite de 4 jugadores era del prototipo.
alter table public.wave_matches drop constraint if exists wave_matches_player_count_check;
alter table public.wave_matches add constraint wave_matches_player_count_check
  check (player_count between 0 and 64);
alter table public.wave_matches add column if not exists max_players integer not null default 20
  check (max_players between 1 and 64);
alter table public.wave_matches add column if not exists mode text not null default 'coop_waves'
  check (mode in ('coop_waves', 'survival', 'horde', 'boss_rush'));
alter table public.wave_matches add column if not exists region text not null default 'auto';
create index if not exists wave_matches_open_idx
  on public.wave_matches(mode, status, player_count) where status in ('lobby', 'active');

-- 2) Los jugadores ya no pueden editar sus resultados.
drop policy if exists "players update own result" on public.wave_match_players;
drop policy if exists "players join matches" on public.wave_match_players;
drop policy if exists "players create lobbies" on public.wave_matches;
drop policy if exists "hosts update lobbies" on public.wave_matches;

-- 3) Estadisticas acumuladas por jugador (alimentan logros y ranking).
create table if not exists public.player_stats (
  user_id uuid primary key references auth.users(id) on delete cascade,
  total_kills integer not null default 0 check (total_kills >= 0),
  elite_kills integer not null default 0 check (elite_kills >= 0),
  boss_kills integer not null default 0 check (boss_kills >= 0),
  revives integer not null default 0 check (revives >= 0),
  times_downed integer not null default 0 check (times_downed >= 0),
  best_wave integer not null default 0 check (best_wave >= 0),
  matches_played integer not null default 0 check (matches_played >= 0),
  matches_won integer not null default 0 check (matches_won >= 0),
  help_calls integer not null default 0 check (help_calls >= 0),
  playtime_seconds bigint not null default 0 check (playtime_seconds >= 0),
  updated_at timestamptz not null default now()
);

-- 4) Catalogo de logros. `metric` + `threshold` permiten desbloquearlos comparando
--    player_stats, sin codigo especifico por logro.
create table if not exists public.achievements (
  id text primary key,
  name text not null,
  description text not null,
  category text not null check (category in ('combate', 'equipo', 'supervivencia', 'exploracion', 'secreto')),
  metric text not null,
  threshold integer not null check (threshold > 0),
  points integer not null default 10 check (points > 0),
  hidden boolean not null default false,
  sort_order integer not null default 0
);

create table if not exists public.player_achievements (
  user_id uuid not null references auth.users(id) on delete cascade,
  achievement_id text not null references public.achievements(id) on delete cascade,
  unlocked_at timestamptz not null default now(),
  match_id uuid references public.wave_matches(id) on delete set null,
  primary key (user_id, achievement_id)
);
create index if not exists player_achievements_user_idx on public.player_achievements(user_id, unlocked_at desc);

insert into public.achievements (id, name, description, category, metric, threshold, points, hidden, sort_order) values
  ('first_blood',      'Primera sangre',        'Elimina a tu primer monstruo.',                        'combate',       'total_kills',   1,     10, false, 10),
  ('exterminator',     'Exterminador',          'Elimina 100 monstruos.',                               'combate',       'total_kills',   100,   25, false, 20),
  ('mass_extinction',  'Extincion masiva',      'Elimina 1.000 monstruos.',                             'combate',       'total_kills',   1000,  60, false, 30),
  ('elite_hunter',     'Cazador de elites',     'Derrota a 10 elites.',                                 'combate',       'elite_kills',   10,    30, false, 40),
  ('boss_slayer',      'Matajefes',             'Derrota a 5 jefes.',                                   'combate',       'boss_kills',    5,     50, false, 50),
  ('medic',            'Medico de guerra',      'Levanta a 10 companeros caidos.',                      'equipo',        'revives',       10,    30, false, 60),
  ('guardian_angel',   'Angel de la guarda',    'Levanta a 50 companeros caidos.',                      'equipo',        'revives',       50,    70, false, 70),
  ('loud_and_clear',   'Fuerte y claro',        'Pide ayuda al equipo 10 veces.',                       'equipo',        'help_calls',    10,    10, false, 80),
  ('wave_5',           'Aguanta el tipo',       'Llega a la oleada 5.',                                 'supervivencia', 'best_wave',     5,     15, false, 90),
  ('wave_10',          'Imparable',             'Llega a la oleada 10.',                                'supervivencia', 'best_wave',     10,    35, false, 100),
  ('wave_20',          'Leyenda de la arena',   'Llega a la oleada 20.',                                'supervivencia', 'best_wave',     20,    80, false, 110),
  ('veteran',          'Veterano',              'Juega 25 partidas.',                                   'supervivencia', 'matches_played',25,    20, false, 120),
  ('marathon',         'Maraton',               'Acumula 10 horas de juego.',                           'supervivencia', 'playtime_seconds', 36000, 40, false, 130),
  ('back_from_dead',   'De entre los muertos',  'Cae 20 veces y sigue peleando.',                       'secreto',       'times_downed',  20,    20, true,  140)
on conflict (id) do update set
  name = excluded.name, description = excluded.description, category = excluded.category,
  metric = excluded.metric, threshold = excluded.threshold, points = excluded.points,
  hidden = excluded.hidden, sort_order = excluded.sort_order;

-- 5) Funcion que aplica el resultado de una partida y desbloquea logros. Solo la puede
--    llamar el servidor (service_role); los jugadores no tienen EXECUTE.
create or replace function public.record_match_result(
  p_user_id uuid,
  p_match_id uuid,
  p_kills integer,
  p_elite_kills integer,
  p_boss_kills integer,
  p_revives integer,
  p_downed integer,
  p_help_calls integer,
  p_wave integer,
  p_won boolean,
  p_seconds integer
) returns setof text
language plpgsql
security definer
set search_path = public
as $$
begin
  insert into public.player_stats as s (user_id, total_kills, elite_kills, boss_kills, revives,
      times_downed, help_calls, best_wave, matches_played, matches_won, playtime_seconds)
  values (p_user_id, greatest(p_kills,0), greatest(p_elite_kills,0), greatest(p_boss_kills,0),
      greatest(p_revives,0), greatest(p_downed,0), greatest(p_help_calls,0), greatest(p_wave,0), 1,
      case when p_won then 1 else 0 end, greatest(p_seconds,0))
  on conflict (user_id) do update set
    total_kills = s.total_kills + greatest(p_kills,0),
    elite_kills = s.elite_kills + greatest(p_elite_kills,0),
    boss_kills = s.boss_kills + greatest(p_boss_kills,0),
    revives = s.revives + greatest(p_revives,0),
    times_downed = s.times_downed + greatest(p_downed,0),
    help_calls = s.help_calls + greatest(p_help_calls,0),
    best_wave = greatest(s.best_wave, greatest(p_wave,0)),
    matches_played = s.matches_played + 1,
    matches_won = s.matches_won + case when p_won then 1 else 0 end,
    playtime_seconds = s.playtime_seconds + greatest(p_seconds,0),
    updated_at = now();

  return query
  with unlocked as (
    insert into public.player_achievements (user_id, achievement_id, match_id)
    select p_user_id, a.id, p_match_id
    from public.achievements a
    join public.player_stats s on s.user_id = p_user_id
    where (case a.metric
             when 'total_kills' then s.total_kills
             when 'elite_kills' then s.elite_kills
             when 'boss_kills' then s.boss_kills
             when 'revives' then s.revives
             when 'times_downed' then s.times_downed
             when 'help_calls' then s.help_calls
             when 'best_wave' then s.best_wave
             when 'matches_played' then s.matches_played
             when 'playtime_seconds' then s.playtime_seconds::integer
             else 0 end) >= a.threshold
    on conflict do nothing
    returning achievement_id
  )
  select achievement_id from unlocked;
end;
$$;
revoke all on function public.record_match_result(uuid, uuid, integer, integer, integer, integer, integer, integer, integer, boolean, integer) from public, anon, authenticated;
grant execute on function public.record_match_result(uuid, uuid, integer, integer, integer, integer, integer, integer, integer, boolean, integer) to service_role;

-- 6) RLS: catalogo y logros desbloqueados son de lectura publica; nadie escribe desde el cliente.
alter table public.player_stats enable row level security;
alter table public.achievements enable row level security;
alter table public.player_achievements enable row level security;
drop policy if exists "stats are publicly readable" on public.player_stats;
create policy "stats are publicly readable" on public.player_stats for select using (true);
drop policy if exists "achievements catalog is public" on public.achievements;
create policy "achievements catalog is public" on public.achievements for select using (hidden = false);
drop policy if exists "unlocked achievements are public" on public.player_achievements;
create policy "unlocked achievements are public" on public.player_achievements for select using (true);

-- 7) Ranking global (top 100 por puntos de logros y mejor oleada).
create or replace view public.leaderboard as
select p.id as user_id, p.display_name,
       coalesce(s.best_wave, 0) as best_wave,
       coalesce(s.total_kills, 0) as total_kills,
       coalesce(sum(a.points), 0)::integer as achievement_points
from public.player_profiles p
left join public.player_stats s on s.user_id = p.id
left join public.player_achievements pa on pa.user_id = p.id
left join public.achievements a on a.id = pa.achievement_id
group by p.id, p.display_name, s.best_wave, s.total_kills
order by achievement_points desc, best_wave desc, total_kills desc
limit 100;
grant select on public.leaderboard to anon, authenticated;
