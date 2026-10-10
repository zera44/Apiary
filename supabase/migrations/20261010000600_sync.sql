-- Забирання змін телефоном (етап 5).
--
-- sync_pull(таблиця, курсор, скільки) - рядки, змінені після курсора, лише
-- з уже завершених транзакцій (server_xid нижче за найстарішу ще відкриту).
-- Курсор - «server_xid:server_seq» останнього отриманого рядка (NULL -
-- від початку). Номер зміни видається ще до завершення транзакції, тож
-- простий «server_seq > N» пропустив би рядки довгої транзакції, що
-- завершилась після коротшої; тут такого немає. Правила доступу діють як
-- завжди (функція працює від імені того, хто викликає).
--
-- Коли помічнику відкривають нову пасіку, її давні рядки лежать «до»
-- курсора - телефон тоді забирає таблиці заново з NULL (етап 5).

create or replace function public.sync_pull(p_table text, p_after text default null, p_limit integer default 500)
returns jsonb
language plpgsql stable security invoker set search_path = public as $$
declare
  horizon xid8 := pg_snapshot_xmin(pg_current_snapshot());
  ax xid8 := '0'::xid8;
  aseq bigint := -1;
  lim integer := least(greatest(coalesce(p_limit, 500), 1), 1000);
  rows jsonb;
  n integer;
begin
  if p_table <> all (array[
    'apiaries', 'elements', 'templates', 'parameters', 'element_parameters',
    'parameter_records', 'qr_codes', 'note_labels', 'hive_notes', 'param_groups',
    'stock_items', 'stock_moves', 'fin_categories', 'fin_ops', 'fin_lines',
    'apiary_members', 'invitations']) then
    raise exception 'невідома таблиця %', p_table using errcode = '22023';
  end if;
  if coalesce(p_after, '') <> '' then
    if p_after !~ '^[0-9]+:-?[0-9]+$' then
      raise exception 'курсор % не такий', p_after using errcode = '22023';
    end if;
    ax := split_part(p_after, ':', 1)::xid8;
    aseq := split_part(p_after, ':', 2)::bigint;
  end if;
  execute format(
    'select coalesce(jsonb_agg(to_jsonb(t) order by t.server_xid, t.server_seq), ''[]''::jsonb) '
    'from (select * from public.%I where (server_xid, server_seq) > ($1, $2) and server_xid < $3 '
    'order by server_xid, server_seq limit $4) t', p_table)
    into rows using ax, aseq, horizon, lim;
  n := jsonb_array_length(rows);
  return jsonb_build_object(
    'rows', rows,
    'next', case when n = 0 then nullif(p_after, '')
                 else (rows -> (n - 1) ->> 'server_xid') || ':' || (rows -> (n - 1) ->> 'server_seq') end,
    'more', n = lim);
end
$$;
revoke execute on function public.sync_pull(text, text, integer) from public, anon;
grant execute on function public.sync_pull(text, text, integer) to authenticated;
