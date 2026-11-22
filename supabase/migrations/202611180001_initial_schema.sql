create extension if not exists pgcrypto;

create type public.user_role as enum ('officer', 'inspector', 'admin');
create type public.stock_condition as enum ('new', 'used_good', 'quarantine', 'damaged');
create type public.funding_source as enum ('company', 'advanced');
create type public.payment_method as enum ('cash', 'transfer');
create type public.reimbursement_status as enum ('not_submitted', 'submitted', 'partially_paid', 'paid');
create type public.stocktake_status as enum ('draft', 'pending_review', 'completed');
create type public.inspection_result as enum ('used_good', 'maintenance', 'damaged', 'lost');

create table public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  full_name text not null,
  role public.user_role not null default 'officer',
  active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.departments (
  id uuid primary key default gen_random_uuid(),
  code text not null unique,
  name text not null unique,
  active boolean not null default true,
  created_at timestamptz not null default now()
);

create table public.employees (
  id uuid primary key default gen_random_uuid(),
  nik text not null unique,
  name text not null,
  position text not null,
  department_id uuid not null references public.departments(id),
  contract_status text not null check (contract_status in ('permanent', 'contract', 'intern', 'inactive')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.suppliers (
  id uuid primary key default gen_random_uuid(),
  code text not null unique,
  name text not null,
  contact_name text,
  phone text,
  address text,
  active boolean not null default true,
  created_at timestamptz not null default now()
);

create table public.funders (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  phone text,
  notes text,
  active boolean not null default true,
  created_at timestamptz not null default now()
);

create table public.items (
  id uuid primary key default gen_random_uuid(),
  code text not null unique,
  name text not null,
  specification text,
  unit text not null,
  minimum_stock numeric(14,2) not null default 0 check (minimum_stock >= 0),
  photo_key text,
  return_required boolean not null default true,
  active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.item_variants (
  id uuid primary key default gen_random_uuid(),
  item_id uuid not null references public.items(id),
  size text not null default '-',
  active boolean not null default true,
  created_at timestamptz not null default now(),
  unique(item_id, size)
);

create table public.stock_balances (
  variant_id uuid not null references public.item_variants(id),
  condition public.stock_condition not null,
  quantity numeric(14,2) not null default 0 check (quantity >= 0),
  updated_at timestamptz not null default now(),
  primary key (variant_id, condition)
);

create table public.purchases (
  id uuid primary key default gen_random_uuid(),
  transaction_no text not null unique,
  purchase_date date not null,
  received_date date not null,
  pr_number text,
  request_number text,
  po_number text,
  delivery_note_number text,
  invoice_number text,
  reason text not null,
  supplier_id uuid not null references public.suppliers(id),
  billing_proof_key text,
  payment_proof_key text,
  total_paid numeric(16,2) not null default 0 check (total_paid >= 0),
  funding_source public.funding_source not null,
  payment_method public.payment_method not null,
  funder_id uuid references public.funders(id),
  reimbursement_status public.reimbursement_status,
  notes text,
  idempotency_key text unique,
  created_by uuid not null references public.profiles(id),
  created_at timestamptz not null default now(),
  check ((funding_source = 'advanced' and funder_id is not null) or funding_source = 'company')
);

create table public.purchase_items (
  id uuid primary key default gen_random_uuid(),
  purchase_id uuid not null references public.purchases(id) on delete restrict,
  variant_id uuid not null references public.item_variants(id),
  quantity numeric(14,2) not null check (quantity > 0),
  condition public.stock_condition not null,
  serial_number text,
  receiver_name text not null,
  receipt_proof_key text,
  notes text,
  created_at timestamptz not null default now()
);

create table public.issuances (
  id uuid primary key default gen_random_uuid(),
  transaction_no text not null unique,
  issued_at date not null,
  employee_id uuid not null references public.employees(id),
  officer_name text not null,
  ba_key text,
  handover_proof_key text,
  notes text,
  idempotency_key text unique,
  created_by uuid not null references public.profiles(id),
  created_at timestamptz not null default now()
);

create table public.issuance_items (
  id uuid primary key default gen_random_uuid(),
  issuance_id uuid not null references public.issuances(id) on delete restrict,
  variant_id uuid not null references public.item_variants(id),
  condition public.stock_condition not null check (condition in ('new', 'used_good')),
  quantity numeric(14,2) not null check (quantity > 0),
  returned_quantity numeric(14,2) not null default 0 check (returned_quantity >= 0),
  resolved_lost_quantity numeric(14,2) not null default 0 check (resolved_lost_quantity >= 0),
  purpose text not null,
  notes text,
  created_at timestamptz not null default now(),
  check (returned_quantity + resolved_lost_quantity <= quantity)
);

create table public.returns (
  id uuid primary key default gen_random_uuid(),
  transaction_no text not null unique,
  returned_at date not null,
  employee_id uuid not null references public.employees(id),
  inspector_name text not null,
  proof_key text,
  idempotency_key text unique,
  created_by uuid not null references public.profiles(id),
  created_at timestamptz not null default now()
);

create table public.return_items (
  id uuid primary key default gen_random_uuid(),
  return_id uuid not null references public.returns(id) on delete restrict,
  issuance_item_id uuid not null references public.issuance_items(id),
  quantity numeric(14,2) not null check (quantity > 0),
  result public.inspection_result not null,
  reason text,
  notes text,
  created_at timestamptz not null default now()
);

create table public.reimbursements (
  id uuid primary key default gen_random_uuid(),
  purchase_id uuid not null references public.purchases(id) on delete restrict,
  reimbursed_at date not null,
  amount numeric(16,2) not null check (amount > 0),
  proof_key text,
  notes text,
  created_by uuid not null references public.profiles(id),
  created_at timestamptz not null default now()
);

create table public.stocktakes (
  id uuid primary key default gen_random_uuid(),
  stocktake_no text not null unique,
  reference_at timestamptz not null,
  officer_name text not null,
  status public.stocktake_status not null default 'draft',
  submitted_at timestamptz,
  finalized_at timestamptz,
  finalized_by uuid references public.profiles(id),
  created_by uuid not null references public.profiles(id),
  created_at timestamptz not null default now()
);

create table public.stocktake_items (
  id uuid primary key default gen_random_uuid(),
  stocktake_id uuid not null references public.stocktakes(id) on delete restrict,
  variant_id uuid not null references public.item_variants(id),
  condition public.stock_condition not null,
  system_quantity numeric(14,2) not null check (system_quantity >= 0),
  physical_quantity numeric(14,2) not null check (physical_quantity >= 0),
  reason text,
  proof_key text,
  adjustment_quantity numeric(14,2),
  created_at timestamptz not null default now(),
  unique(stocktake_id, variant_id, condition)
);

create table public.stock_movements (
  id bigint generated always as identity primary key,
  variant_id uuid not null references public.item_variants(id),
  condition public.stock_condition not null,
  quantity_delta numeric(14,2) not null check (quantity_delta <> 0),
  balance_after numeric(14,2) not null check (balance_after >= 0),
  movement_type text not null check (movement_type in ('receipt', 'issuance', 'return', 'stocktake_adjustment', 'condition_transfer')),
  reference_type text not null,
  reference_id uuid not null,
  notes text,
  occurred_at timestamptz not null default now(),
  created_by uuid not null references public.profiles(id)
);

create index stock_movements_variant_time_idx on public.stock_movements(variant_id, occurred_at desc);
create index issuance_items_variant_idx on public.issuance_items(variant_id);
create index issuances_employee_idx on public.issuances(employee_id, issued_at desc);
create index purchase_items_purchase_idx on public.purchase_items(purchase_id);
create index return_items_issuance_item_idx on public.return_items(issuance_item_id);

create or replace function public.touch_updated_at()
returns trigger language plpgsql as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

create trigger profiles_touch before update on public.profiles for each row execute function public.touch_updated_at();
create trigger employees_touch before update on public.employees for each row execute function public.touch_updated_at();
create trigger items_touch before update on public.items for each row execute function public.touch_updated_at();

create or replace function public.handle_new_user()
returns trigger security definer set search_path = public language plpgsql as $$
begin
  insert into public.profiles (id, full_name)
  values (new.id, coalesce(new.raw_user_meta_data ->> 'full_name', new.email, 'Pengguna'));
  return new;
end;
$$;

create trigger on_auth_user_created after insert on auth.users
for each row execute function public.handle_new_user();

create or replace function public.current_user_role()
returns public.user_role language sql stable security definer set search_path = public as $$
  select role from public.profiles where id = auth.uid() and active = true
$$;

create view public.inventory_view with (security_invoker = true) as
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

alter table public.profiles enable row level security;
alter table public.departments enable row level security;
alter table public.employees enable row level security;
alter table public.suppliers enable row level security;
alter table public.funders enable row level security;
alter table public.items enable row level security;
alter table public.item_variants enable row level security;
alter table public.stock_balances enable row level security;
alter table public.purchases enable row level security;
alter table public.purchase_items enable row level security;
alter table public.issuances enable row level security;
alter table public.issuance_items enable row level security;
alter table public.returns enable row level security;
alter table public.return_items enable row level security;
alter table public.reimbursements enable row level security;
alter table public.stocktakes enable row level security;
alter table public.stocktake_items enable row level security;
alter table public.stock_movements enable row level security;

create policy profiles_read_self on public.profiles for select to authenticated using (id = auth.uid() or public.current_user_role() = 'admin');
create policy profiles_admin_write on public.profiles for update to authenticated using (public.current_user_role() = 'admin') with check (public.current_user_role() = 'admin');

do $$
declare table_name text;
begin
  foreach table_name in array array[
    'departments','employees','suppliers','funders','items','item_variants',
    'stock_balances','purchases','purchase_items','issuances','issuance_items','returns',
    'return_items','reimbursements','stocktakes','stocktake_items','stock_movements'
  ] loop
    execute format('create policy %I on public.%I for select to authenticated using (public.current_user_role() is not null)', table_name || '_read', table_name);
  end loop;
end $$;

create policy departments_admin_write on public.departments for all to authenticated using (public.current_user_role() = 'admin') with check (public.current_user_role() = 'admin');
create policy employees_admin_write on public.employees for all to authenticated using (public.current_user_role() = 'admin') with check (public.current_user_role() = 'admin');
create policy suppliers_admin_write on public.suppliers for all to authenticated using (public.current_user_role() = 'admin') with check (public.current_user_role() = 'admin');
create policy funders_admin_write on public.funders for all to authenticated using (public.current_user_role() = 'admin') with check (public.current_user_role() = 'admin');
create policy items_admin_write on public.items for all to authenticated using (public.current_user_role() = 'admin') with check (public.current_user_role() = 'admin');
create policy item_variants_admin_write on public.item_variants for all to authenticated using (public.current_user_role() = 'admin') with check (public.current_user_role() = 'admin');

revoke insert, update, delete on public.stock_balances, public.stock_movements from authenticated;
revoke insert, update, delete on public.purchase_items, public.issuance_items, public.return_items, public.reimbursements from authenticated;

grant select on public.inventory_view to authenticated;
grant usage on schema public to authenticated;
