-- Hapus kolom category_id & tabel categories sepenuhnya dari database

drop view if exists public.inventory_view cascade;
alter table public.items drop column if exists category_id cascade;
drop table if exists public.categories cascade;

create or replace view public.inventory_view with (security_invoker = true) as
select
  v.id as variant_id,
  i.id as item_id,
  i.code,
  i.name,
  i.specification,
  v.size,
  i.unit,
  i.minimum_stock,
  i.return_required,
  i.photo_key,
  coalesce(sum(b.quantity) filter (where b.condition = 'new'), 0) as stock_new,
  coalesce(sum(b.quantity) filter (where b.condition = 'used_good'), 0) as stock_used_good,
  coalesce(sum(b.quantity) filter (where b.condition = 'quarantine'), 0) as stock_quarantine,
  coalesce(sum(b.quantity) filter (where b.condition = 'damaged'), 0) as stock_damaged,
  coalesce(sum(b.quantity) filter (where b.condition in ('new', 'used_good')), 0) as total_available,
  case
    when coalesce(sum(b.quantity) filter (where b.condition in ('new', 'used_good')), 0) = 0 then 'out'
    when coalesce(sum(b.quantity) filter (where b.condition in ('new', 'used_good')), 0) <= i.minimum_stock then 'low'
    else 'safe'
  end as stock_status
from public.item_variants v
join public.items i on i.id = v.item_id
left join public.stock_balances b on b.variant_id = v.id
where i.active = true and v.active = true
group by v.id, i.id;

grant select on public.inventory_view to authenticated;
grant usage on schema public to postgres, anon, authenticated, service_role;
grant all privileges on all tables in schema public to postgres, service_role;
grant all privileges on all sequences in schema public to postgres, service_role;
grant all privileges on all functions in schema public to postgres, service_role;
alter default privileges in schema public grant all on tables to postgres, service_role;
alter default privileges in schema public grant all on sequences to postgres, service_role;
alter default privileges in schema public grant all on functions to postgres, service_role;
