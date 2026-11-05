-- Фото чеків для вдосконалення розпізнавання: людина дає згоду в застосунку,
-- застосунок надсилає фото функції receipt-photo, яка кладе його сюди.
--
--   receipt-training/<device_id>/<ггггммдд>-<хеш>.jpg
--
-- Сховище закрите: політик для ролей anon і authenticated немає, пише й
-- читає лише службовий ключ (функція і розробник).

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('receipt-training', 'receipt-training', false, 6291456, array['image/jpeg'])
on conflict (id) do update
  set public = false, file_size_limit = excluded.file_size_limit,
      allowed_mime_types = excluded.allowed_mime_types;
