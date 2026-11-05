-- 003: foto de perfil persistente para los comentarios del sitio.
--
-- La foto se guarda en Supabase Storage (bucket publico "avatars") y la URL
-- queda en site_profiles. Cada comentario copia la URL para no depender de un
-- join en la API publica.

create table if not exists public.site_profiles (
  user_id uuid primary key references auth.users(id) on delete cascade,
  display_name text,
  avatar_url text,
  updated_at timestamptz not null default now()
);

alter table public.site_profiles enable row level security;

drop policy if exists "site_profiles lectura publica" on public.site_profiles;
create policy "site_profiles lectura publica"
  on public.site_profiles for select
  using (true);

-- Escritura solo con la service_role (que salta RLS), nunca desde el navegador.
drop policy if exists "site_profiles escritura servicio" on public.site_profiles;
create policy "site_profiles escritura servicio"
  on public.site_profiles for all
  using (auth.role() = 'service_role')
  with check (auth.role() = 'service_role');

alter table public.game_comments add column if not exists user_id uuid;
alter table public.game_comments add column if not exists avatar_url text;

create index if not exists game_comments_user_idx on public.game_comments (user_id);

-- Bucket publico para las fotos: maximo 2 MB por archivo, solo imagenes.
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('avatars', 'avatars', true, 2097152, array['image/png', 'image/jpeg', 'image/webp'])
on conflict (id) do update
  set public = true,
      file_size_limit = 2097152,
      allowed_mime_types = array['image/png', 'image/jpeg', 'image/webp'];

drop policy if exists "avatars lectura publica" on storage.objects;
create policy "avatars lectura publica"
  on storage.objects for select
  using (bucket_id = 'avatars');

drop policy if exists "avatars escritura servicio" on storage.objects;
create policy "avatars escritura servicio"
  on storage.objects for all
  using (bucket_id = 'avatars' and auth.role() = 'service_role')
  with check (bucket_id = 'avatars' and auth.role() = 'service_role');
