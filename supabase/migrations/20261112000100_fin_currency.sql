-- Валюти рахунків фінансів: валюта рахунку, сума операції у валюті рахунку
-- і сума, що надійшла на рахунок переказу. Застосувати ДО встановлення
-- збірки з цими змінами (колонки на телефоні вже йдуть у синхронізацію).

alter table public.fin_accounts add column if not exists currency text;
alter table public.fin_ops add column if not exists account_amount double precision;
alter table public.fin_transfers add column if not exists to_amount double precision;
