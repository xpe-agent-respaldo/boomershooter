-- Comentarios publicos de la web. Requiere Supabase Auth (email/password).
-- Ejecutar en Supabase SQL Editor.

create table if not exists public.game_comments (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  display_name text not null default 'player' check (char_length(display_name) between 1 and 32),
  content text not null check (char_length(content) between 1 and 500),
  created_at timestamptz not null default now()
);

alter table public.game_comments enable row level security;

drop policy if exists "comments are publicly readable" on public.game_comments;
create policy "comments are publicly readable"
  on public.game_comments for select using (true);

drop policy if exists "users write own comments" on public.game_comments;
create policy "users write own comments"
  on public.game_comments for insert with check (auth.uid() = user_id);

drop policy if exists "users delete own comments" on public.game_comments;
create policy "users delete own comments"
  on public.game_comments for delete using (auth.uid() = user_id);

create index if not exists game_comments_created_idx on public.game_comments (created_at desc);

