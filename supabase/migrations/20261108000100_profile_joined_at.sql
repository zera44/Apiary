-- Дата приєднання користувача: коли він уперше увійшов через обліковий запис
-- (Google). Це час створення запису в auth.users - Supabase створює його саме
-- при першому вході. created_at профілю для давніх користувачів - час
-- міграції, тож він для цього не годиться.

alter table public.profiles add column if not exists joined_at timestamptz;

create or replace function public.trg_profile_from_user() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  insert into public.profiles (id, email, name, joined_at)
  values (new.id, lower(trim(coalesce(new.email, ''))),
          coalesce(new.raw_user_meta_data ->> 'full_name', new.raw_user_meta_data ->> 'name'),
          coalesce(new.created_at, now()))
  on conflict (id) do update set email = excluded.email, name = excluded.name,
    joined_at = coalesce(public.profiles.joined_at, excluded.joined_at);
  return new;
end
$$;

-- ті, хто приєднався раніше: дата з auth.users
update public.profiles p
set joined_at = coalesce(u.created_at, p.created_at)
from auth.users u
where u.id = p.id and p.joined_at is null;

alter table public.profiles alter column joined_at set default now();
alter table public.profiles alter column joined_at set not null;
