-- Файли: фото складу і нічні повні копії бази телефона.
--
--   stock-photos/<власник>/<назва>.webp - фото позицій складу (у базі
--       телефона - лише <назва>.webp). Бачать і додають власник і помічник
--       із дозволом «Також склад і фінанси».
--   backups/<користувач>/<id>.db.gz - стиснена повна копія бази. Лише своя.
--       Сервер тримає 2 непошкоджені: нову спершу перевіряє (функція
--       backup-commit), і лише потім видаляє найстарішу.

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('stock-photos', 'stock-photos', false, 5242880, array['image/webp', 'image/jpeg'])
on conflict (id) do update
  set public = false, file_size_limit = excluded.file_size_limit,
      allowed_mime_types = excluded.allowed_mime_types;

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('backups', 'backups', false, 52428800, array['application/gzip'])
on conflict (id) do update
  set public = false, file_size_limit = excluded.file_size_limit,
      allowed_mime_types = excluded.allowed_mime_types;

-- Власник з шляху «<uuid>/...» (NULL - шлях не такий).
create or replace function public.path_owner(name text) returns uuid
language sql immutable as $$
  select case when (storage.foldername(name))[1] ~ '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
              then ((storage.foldername(name))[1])::uuid end
$$;

drop policy if exists "vulyk photos read" on storage.objects;
drop policy if exists "vulyk photos add" on storage.objects;
drop policy if exists "vulyk photos change" on storage.objects;
drop policy if exists "vulyk photos remove" on storage.objects;
drop policy if exists "vulyk backups read" on storage.objects;
drop policy if exists "vulyk backups add" on storage.objects;

create policy "vulyk photos read" on storage.objects for select to authenticated
  using (bucket_id = 'stock-photos' and public.can_stock(public.path_owner(name)));
create policy "vulyk photos add" on storage.objects for insert to authenticated
  with check (bucket_id = 'stock-photos' and public.can_stock(public.path_owner(name)));
create policy "vulyk photos change" on storage.objects for update to authenticated
  using (bucket_id = 'stock-photos' and public.can_stock(public.path_owner(name)))
  with check (bucket_id = 'stock-photos' and public.can_stock(public.path_owner(name)));
create policy "vulyk photos remove" on storage.objects for delete to authenticated
  using (bucket_id = 'stock-photos' and public.can_stock(public.path_owner(name)));

-- копії: лише свої, лише додати й прочитати (не перезаписати й не видалити -
-- зіпсований телефон не знищить непошкоджені копії)
create policy "vulyk backups read" on storage.objects for select to authenticated
  using (bucket_id = 'backups' and public.path_owner(name) = auth.uid());
create policy "vulyk backups add" on storage.objects for insert to authenticated
  with check (bucket_id = 'backups' and public.path_owner(name) = auth.uid());

-- ── облік нічних копій ──────────────────────────────────────────────────
create table if not exists public.device_backups (
  id text primary key check (id ~ '^[0-9A-Za-z-]{8,64}$'),
  user_id uuid not null default auth.uid() references auth.users (id) on delete cascade,
  path text not null unique,
  size bigint not null check (size > 0),
  sha256 text not null check (sha256 ~ '^[0-9a-f]{64}$'),
  schema_v integer not null,
  device text,
  status text not null default 'uploading' check (status in ('uploading', 'ok', 'bad')),
  reason text,
  created_at timestamptz not null default now(),
  verified_at timestamptz
);
create index if not exists device_backups_user on public.device_backups (user_id, created_at desc);

alter table public.device_backups enable row level security;
revoke all on public.device_backups from anon;
revoke update, delete, truncate on public.device_backups from authenticated;
drop policy if exists read on public.device_backups;
drop policy if exists add on public.device_backups;
create policy read on public.device_backups for select to authenticated
  using (user_id = auth.uid());
-- телефон лише заявляє копію; «ok» ставить сервер після перевірки
create policy add on public.device_backups for insert to authenticated
  with check (user_id = auth.uid() and status = 'uploading' and verified_at is null
              and reason is null and path = auth.uid()::text || '/' || id || '.db.gz');
