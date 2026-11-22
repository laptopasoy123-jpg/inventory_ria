-- FULL SETUP ALL-IN-ONE (Urutan otomatis seluruh migrasi Inventaris APD)

-- ===========================================================
-- MIGRATION: 202611180001_initial_schema.sql
-- ===========================================================
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


-- ===========================================================
-- MIGRATION: 202611180002_transaction_functions.sql
-- ===========================================================
create sequence if not exists public.purchase_no_seq;
create sequence if not exists public.issuance_no_seq;
create sequence if not exists public.return_no_seq;
create sequence if not exists public.stocktake_no_seq;

create or replace function public.next_document_no(p_prefix text, p_sequence regclass)
returns text language plpgsql volatile set search_path = public as $$
declare n bigint;
begin
  n := nextval(p_sequence);
  return p_prefix || '-' || to_char(current_date, 'YYYYMM') || '-' || lpad(n::text, 5, '0');
end;
$$;

create or replace function public.apply_stock_movement(
  p_variant_id uuid,
  p_condition public.stock_condition,
  p_delta numeric,
  p_movement_type text,
  p_reference_type text,
  p_reference_id uuid,
  p_actor uuid,
  p_notes text default null,
  p_occurred_at timestamptz default now()
) returns numeric
language plpgsql security definer set search_path = public as $$
declare current_quantity numeric;
declare next_quantity numeric;
begin
  if p_delta = 0 then
    raise exception 'Jumlah mutasi tidak boleh nol';
  end if;

  insert into public.stock_balances (variant_id, condition, quantity)
  values (p_variant_id, p_condition, 0)
  on conflict (variant_id, condition) do nothing;

  select quantity into current_quantity
  from public.stock_balances
  where variant_id = p_variant_id and condition = p_condition
  for update;

  next_quantity := current_quantity + p_delta;
  if next_quantity < 0 then
    raise exception 'Stok tidak mencukupi. Saldo %, perubahan %', current_quantity, p_delta;
  end if;

  update public.stock_balances
  set quantity = next_quantity, updated_at = now()
  where variant_id = p_variant_id and condition = p_condition;

  insert into public.stock_movements (
    variant_id, condition, quantity_delta, balance_after, movement_type,
    reference_type, reference_id, notes, occurred_at, created_by
  ) values (
    p_variant_id, p_condition, p_delta, next_quantity, p_movement_type,
    p_reference_type, p_reference_id, p_notes, p_occurred_at, p_actor
  );
  return next_quantity;
end;
$$;

create or replace function public.create_purchase_receipt(p_payload jsonb, p_actor uuid)
returns uuid language plpgsql security definer set search_path = public as $$
declare purchase_id uuid;
declare line jsonb;
declare key text := p_payload ->> 'idempotencyKey';
begin
  if key is not null then
    select id into purchase_id from public.purchases where idempotency_key = key;
    if purchase_id is not null then return purchase_id; end if;
  end if;

  insert into public.purchases (
    transaction_no, purchase_date, received_date, pr_number, request_number, po_number,
    delivery_note_number, invoice_number, reason, supplier_id, billing_proof_key,
    payment_proof_key, total_paid, funding_source, payment_method, funder_id,
    reimbursement_status, idempotency_key, created_by
  ) values (
    public.next_document_no('PB', 'public.purchase_no_seq'),
    (p_payload ->> 'purchaseDate')::timestamptz::date,
    (p_payload ->> 'receivedDate')::timestamptz::date,
    nullif(p_payload ->> 'prNumber', ''), nullif(p_payload ->> 'requestNumber', ''),
    nullif(p_payload ->> 'poNumber', ''), nullif(p_payload ->> 'deliveryNoteNumber', ''),
    nullif(p_payload ->> 'invoiceNumber', ''), p_payload ->> 'reason',
    (p_payload ->> 'supplierId')::uuid, nullif(p_payload ->> 'billingProofKey', ''),
    nullif(p_payload ->> 'paymentProofKey', ''), (p_payload ->> 'totalPaid')::numeric,
    (p_payload ->> 'fundingSource')::public.funding_source,
    (p_payload ->> 'paymentMethod')::public.payment_method,
    nullif(p_payload ->> 'funderId', '')::uuid,
    case when p_payload ->> 'fundingSource' = 'advanced' then 'not_submitted'::public.reimbursement_status else null end,
    key, p_actor
  ) returning id into purchase_id;

  for line in select * from jsonb_array_elements(p_payload -> 'items') loop
    insert into public.purchase_items (
      purchase_id, variant_id, quantity, condition, serial_number, receiver_name, receipt_proof_key, notes
    ) values (
      purchase_id, (line ->> 'variantId')::uuid, (line ->> 'quantity')::numeric,
      (line ->> 'condition')::public.stock_condition, nullif(line ->> 'serialNumber', ''),
      line ->> 'receiverName', nullif(line ->> 'receiptProofKey', ''), nullif(line ->> 'notes', '')
    );

    perform public.apply_stock_movement(
      (line ->> 'variantId')::uuid, (line ->> 'condition')::public.stock_condition,
      (line ->> 'quantity')::numeric, 'receipt', 'purchase', purchase_id, p_actor,
      'Penerimaan pembelian', (p_payload ->> 'receivedDate')::timestamptz
    );
  end loop;
  return purchase_id;
end;
$$;

create or replace function public.create_issuance(p_payload jsonb, p_actor uuid)
returns uuid language plpgsql security definer set search_path = public as $$
declare issuance_id uuid;
declare line jsonb;
declare key text := p_payload ->> 'idempotencyKey';
declare v_condition public.stock_condition;
begin
  if key is not null then
    select id into issuance_id from public.issuances where idempotency_key = key;
    if issuance_id is not null then return issuance_id; end if;
  end if;

  insert into public.issuances (
    transaction_no, issued_at, employee_id, officer_name, ba_key, handover_proof_key,
    notes, idempotency_key, created_by
  ) values (
    public.next_document_no('BK', 'public.issuance_no_seq'),
    (p_payload ->> 'issuedAt')::timestamptz::date, (p_payload ->> 'employeeId')::uuid,
    p_payload ->> 'officerName', nullif(p_payload ->> 'baKey', ''),
    nullif(p_payload ->> 'handoverProofKey', ''), nullif(p_payload ->> 'notes', ''), key, p_actor
  ) returning id into issuance_id;

  for line in select * from jsonb_array_elements(p_payload -> 'items') loop
    v_condition := (line ->> 'condition')::public.stock_condition;
    if v_condition not in ('new', 'used_good') then
      raise exception 'Kondisi karantina atau rusak tidak dapat dikeluarkan';
    end if;

    insert into public.issuance_items (issuance_id, variant_id, condition, quantity, purpose, notes)
    values (
      issuance_id, (line ->> 'variantId')::uuid, v_condition,
      (line ->> 'quantity')::numeric, line ->> 'purpose', nullif(line ->> 'notes', '')
    );

    perform public.apply_stock_movement(
      (line ->> 'variantId')::uuid, v_condition, -(line ->> 'quantity')::numeric,
      'issuance', 'issuance', issuance_id, p_actor, line ->> 'purpose',
      (p_payload ->> 'issuedAt')::timestamptz
    );
  end loop;
  return issuance_id;
end;
$$;

create or replace function public.create_return(p_payload jsonb, p_actor uuid)
returns uuid language plpgsql security definer set search_path = public as $$
declare return_id uuid;
declare line jsonb;
declare issue_line public.issuance_items%rowtype;
declare issue_employee uuid;
declare remaining numeric;
declare result public.inspection_result;
declare target_condition public.stock_condition;
declare key text := p_payload ->> 'idempotencyKey';
begin
  if key is not null then
    select id into return_id from public.returns where idempotency_key = key;
    if return_id is not null then return return_id; end if;
  end if;

  insert into public.returns (transaction_no, returned_at, employee_id, inspector_name, proof_key, idempotency_key, created_by)
  values (
    public.next_document_no('PG', 'public.return_no_seq'),
    (p_payload ->> 'returnedAt')::timestamptz::date, (p_payload ->> 'employeeId')::uuid,
    p_payload ->> 'inspectorName', nullif(p_payload ->> 'proofKey', ''), key, p_actor
  ) returning id into return_id;

  for line in select * from jsonb_array_elements(p_payload -> 'items') loop
    select ii.* into issue_line
    from public.issuance_items ii
    where ii.id = (line ->> 'issuanceItemId')::uuid
    for update;

    if issue_line.id is null then raise exception 'Detail pengeluaran tidak ditemukan'; end if;

    select employee_id into issue_employee
    from public.issuances
    where id = issue_line.issuance_id;

    if issue_employee <> (p_payload ->> 'employeeId')::uuid then
      raise exception 'Pengeluaran tidak dimiliki karyawan yang dipilih';
    end if;

    remaining := issue_line.quantity - issue_line.returned_quantity - issue_line.resolved_lost_quantity;
    if (line ->> 'quantity')::numeric > remaining then
      raise exception 'Jumlah pengembalian melebihi sisa tanggungan %', remaining;
    end if;

    result := (line ->> 'inspectionResult')::public.inspection_result;
    if result = 'lost' and nullif(line ->> 'reason', '') is null then
      raise exception 'Alasan wajib diisi untuk penyelesaian kehilangan';
    end if;

    insert into public.return_items (return_id, issuance_item_id, quantity, result, reason, notes)
    values (
      return_id, issue_line.id, (line ->> 'quantity')::numeric, result,
      nullif(line ->> 'reason', ''), nullif(line ->> 'notes', '')
    );

    if result = 'lost' then
      update public.issuance_items
      set resolved_lost_quantity = resolved_lost_quantity + (line ->> 'quantity')::numeric
      where id = issue_line.id;
    else
      update public.issuance_items
      set returned_quantity = returned_quantity + (line ->> 'quantity')::numeric
      where id = issue_line.id;

      target_condition := case result
        when 'used_good' then 'used_good'::public.stock_condition
        when 'maintenance' then 'quarantine'::public.stock_condition
        when 'damaged' then 'damaged'::public.stock_condition
      end;
      perform public.apply_stock_movement(
        issue_line.variant_id, target_condition, (line ->> 'quantity')::numeric,
        'return', 'return', return_id, p_actor, coalesce(line ->> 'reason', 'Pengembalian APD'),
        (p_payload ->> 'returnedAt')::timestamptz
      );
    end if;
  end loop;
  return return_id;
end;
$$;

create or replace function public.create_reimbursement(p_payload jsonb, p_actor uuid)
returns uuid language plpgsql security definer set search_path = public as $$
declare reimbursement_id uuid;
declare purchase_row public.purchases%rowtype;
declare already_paid numeric;
declare requested numeric := (p_payload ->> 'amount')::numeric;
declare remaining numeric;
begin
  select * into purchase_row from public.purchases
  where id = (p_payload ->> 'purchaseId')::uuid for update;
  if purchase_row.id is null then raise exception 'Pembelian tidak ditemukan'; end if;
  if purchase_row.funding_source <> 'advanced' then raise exception 'Pembelian perusahaan tidak memiliki reimbursement'; end if;

  select coalesce(sum(amount), 0) into already_paid
  from public.reimbursements where purchase_id = purchase_row.id;
  remaining := purchase_row.total_paid - already_paid;
  if requested > remaining then raise exception 'Penggantian melebihi sisa reimbursement %', remaining; end if;

  insert into public.reimbursements (purchase_id, reimbursed_at, amount, proof_key, notes, created_by)
  values (
    purchase_row.id, (p_payload ->> 'reimbursedAt')::timestamptz::date, requested,
    nullif(p_payload ->> 'proofKey', ''), nullif(p_payload ->> 'notes', ''), p_actor
  ) returning id into reimbursement_id;

  update public.purchases set reimbursement_status =
    case when requested = remaining then 'paid'::public.reimbursement_status
         else 'partially_paid'::public.reimbursement_status end
  where id = purchase_row.id;
  return reimbursement_id;
end;
$$;

create or replace function public.finalize_stocktake(p_stocktake_id uuid, p_actor uuid)
returns uuid language plpgsql security definer set search_path = public as $$
declare stocktake_row public.stocktakes%rowtype;
declare line public.stocktake_items%rowtype;
declare movement_since numeric;
declare expected_now numeric;
declare adjustment numeric;
begin
  select * into stocktake_row from public.stocktakes where id = p_stocktake_id for update;
  if stocktake_row.id is null then raise exception 'Stok opname tidak ditemukan'; end if;
  if stocktake_row.status <> 'pending_review' then raise exception 'Stok opname harus berstatus Menunggu Pemeriksaan'; end if;
  if stocktake_row.finalized_at is not null then raise exception 'Stok opname sudah pernah difinalisasi'; end if;

  for line in select * from public.stocktake_items where stocktake_id = p_stocktake_id order by variant_id, condition loop
    select coalesce(sum(quantity_delta), 0) into movement_since
    from public.stock_movements
    where variant_id = line.variant_id and condition = line.condition
      and occurred_at > stocktake_row.reference_at;
    expected_now := line.physical_quantity + movement_since;

    insert into public.stock_balances (variant_id, condition, quantity)
    values (line.variant_id, line.condition, 0)
    on conflict (variant_id, condition) do nothing;
    perform 1 from public.stock_balances
      where variant_id = line.variant_id and condition = line.condition for update;

    select expected_now - quantity into adjustment from public.stock_balances
    where variant_id = line.variant_id and condition = line.condition;

    if adjustment <> 0 then
      perform public.apply_stock_movement(
        line.variant_id, line.condition, adjustment, 'stocktake_adjustment', 'stocktake',
        p_stocktake_id, p_actor, line.reason, now()
      );
    end if;
    update public.stocktake_items set adjustment_quantity = adjustment where id = line.id;
  end loop;

  update public.stocktakes
  set status = 'completed', finalized_at = now(), finalized_by = p_actor
  where id = p_stocktake_id;
  return p_stocktake_id;
end;
$$;

create or replace function public.dashboard_summary(p_month int, p_year int)
returns jsonb language sql stable security definer set search_path = public as $$
with period as (
  select make_date(p_year, p_month, 1)::timestamptz as start_at,
         (make_date(p_year, p_month, 1) + interval '1 month')::timestamptz as end_at
), cards as (
  select
    (select count(*) from public.items where active) as item_types,
    (select count(*) from public.inventory_view where stock_status = 'low') as low_stock_types,
    (select count(*) from public.inventory_view where stock_status = 'out') as out_stock_types,
    (select count(*) from public.purchases p, period x where p.created_at >= x.start_at and p.created_at < x.end_at) as purchase_count
), unit_totals as (
  select jsonb_agg(jsonb_build_object('unit', unit, 'quantity', quantity) order by unit) as value
  from (
    select unit, sum(total_available) quantity from public.inventory_view group by unit
  ) q
), monthly as (
  select jsonb_agg(jsonb_build_object('month', label, 'unit', unit, 'incoming', incoming, 'outgoing', outgoing) order by month_start, unit) as value
  from (
    select m.month_start, to_char(m.month_start, 'Mon') label, i.unit,
      coalesce(sum(sm.quantity_delta) filter (where sm.quantity_delta > 0 and sm.movement_type = 'receipt'), 0) incoming,
      abs(coalesce(sum(sm.quantity_delta) filter (where sm.quantity_delta < 0 and sm.movement_type = 'issuance'), 0)) outgoing
    from generate_series(make_date(p_year, 1, 1), make_date(p_year, 12, 1), interval '1 month') m(month_start)
    cross join (select distinct unit from public.items where active) i
    left join public.stock_movements sm on date_trunc('month', sm.occurred_at) = m.month_start
      and exists (select 1 from public.item_variants iv join public.items it on it.id = iv.item_id where iv.id = sm.variant_id and it.unit = i.unit)
    group by m.month_start, i.unit
  ) q
), low_items as (
  select coalesce(jsonb_agg(to_jsonb(q)), '[]'::jsonb) as value from (
    select variant_id, code, name, size, unit, total_available, minimum_stock, stock_status
    from public.inventory_view where stock_status in ('low', 'out')
    order by total_available, name limit 8
  ) q
), flow as (
  select coalesce(jsonb_agg(jsonb_build_object('unit', unit, 'incoming', incoming, 'outgoing', outgoing) order by unit), '[]'::jsonb) as value
  from (
    select i.unit,
      coalesce(sum(sm.quantity_delta) filter (where sm.quantity_delta > 0 and sm.movement_type = 'receipt'), 0) incoming,
      abs(coalesce(sum(sm.quantity_delta) filter (where sm.quantity_delta < 0 and sm.movement_type = 'issuance'), 0)) outgoing
    from public.items i
    join public.item_variants iv on iv.item_id = i.id
    cross join period
    left join public.stock_movements sm on sm.variant_id = iv.id
      and sm.occurred_at >= period.start_at and sm.occurred_at < period.end_at
    group by i.unit
  ) q
)
select jsonb_build_object(
  'itemTypes', cards.item_types,
  'stockByUnit', coalesce(unit_totals.value, '[]'::jsonb),
  'lowStockTypes', cards.low_stock_types,
  'outStockTypes', cards.out_stock_types,
  'purchaseCount', cards.purchase_count,
  'periodFlow', flow.value,
  'monthlyFlow', coalesce(monthly.value, '[]'::jsonb),
  'attentionItems', low_items.value
)
from cards, unit_totals, monthly, low_items, flow
$$;

grant execute on function public.dashboard_summary(int, int) to authenticated;
revoke execute on function public.apply_stock_movement(uuid, public.stock_condition, numeric, text, text, uuid, uuid, text, timestamptz) from public, authenticated;
revoke execute on function public.create_purchase_receipt(jsonb, uuid) from public, authenticated;
revoke execute on function public.create_issuance(jsonb, uuid) from public, authenticated;
revoke execute on function public.create_return(jsonb, uuid) from public, authenticated;
revoke execute on function public.create_reimbursement(jsonb, uuid) from public, authenticated;
revoke execute on function public.finalize_stocktake(uuid, uuid) from public, authenticated;


-- ===========================================================
-- MIGRATION: 202611180003_nullable_created_by.sql
-- ===========================================================
alter table public.purchases alter column created_by drop not null;
alter table public.issuances alter column created_by drop not null;
alter table public.returns alter column created_by drop not null;
alter table public.reimbursements alter column created_by drop not null;
alter table public.stocktakes alter column created_by drop not null;
alter table public.stock_movements alter column created_by drop not null;


-- ===========================================================
-- MIGRATION: 202611190001_procurements_and_opening_stock.sql
-- ===========================================================
-- Migration: Opening Stock, Procurements, Procurement Payments, Condition Transfer & Stocktake Creation

alter table public.stock_movements drop constraint if exists stock_movements_movement_type_check;
alter table public.stock_movements add constraint stock_movements_movement_type_check
  check (movement_type in ('opening_stock', 'receipt', 'issuance', 'return', 'stocktake_adjustment', 'condition_transfer'));

create sequence if not exists public.opening_stock_no_seq;
create sequence if not exists public.procurement_no_seq;

-- 0. System Officers (Pengaturan Nama Petugas / Penerima / Inspektor)
create table if not exists public.system_officers (
  id uuid primary key default gen_random_uuid(),
  name text not null unique,
  role_label text not null default 'Petugas Gudang',
  active boolean not null default true,
  created_at timestamptz not null default now()
);

alter table public.system_officers enable row level security;
drop policy if exists system_officers_read on public.system_officers;
create policy system_officers_read on public.system_officers for select to authenticated using (public.current_user_role() is not null);
drop policy if exists system_officers_admin_write on public.system_officers;
create policy system_officers_admin_write on public.system_officers for all to authenticated using (public.current_user_role() = 'admin') with check (public.current_user_role() = 'admin');

-- 1. Opening Stocks (Stok Awal)
create table if not exists public.opening_stocks (
  id uuid primary key default gen_random_uuid(),
  transaction_no text not null unique,
  recorded_at date not null,
  officer_name text not null,
  notes text,
  idempotency_key text unique,
  created_by uuid references public.profiles(id),
  created_at timestamptz not null default now()
);

create table if not exists public.opening_stock_items (
  id uuid primary key default gen_random_uuid(),
  opening_stock_id uuid not null references public.opening_stocks(id) on delete cascade,
  variant_id uuid not null references public.item_variants(id),
  condition public.stock_condition not null,
  quantity numeric(14,2) not null check (quantity > 0),
  notes text,
  created_at timestamptz not null default now()
);

-- 2. Procurements (Database Pengadaan Barang)
create table if not exists public.procurements (
  id uuid primary key default gen_random_uuid(),
  procurement_no text not null unique,
  procurement_date date not null,
  expected_date date,
  pr_number text,
  po_number text,
  department_id uuid references public.departments(id),
  supplier_id uuid not null references public.suppliers(id),
  reason text not null,
  funding_source public.funding_source not null default 'company',
  payment_method public.payment_method not null default 'transfer',
  funder_id uuid references public.funders(id),
  total_amount numeric(16,2) not null default 0 check (total_amount >= 0),
  paid_amount numeric(16,2) not null default 0 check (paid_amount >= 0),
  payment_status text not null default 'unpaid' check (payment_status in ('unpaid', 'partial', 'paid')),
  reimbursement_status public.reimbursement_status,
  status text not null default 'ordered' check (status in ('draft', 'ordered', 'partial', 'completed', 'cancelled')),
  document_key text,
  notes text,
  idempotency_key text unique,
  created_by uuid references public.profiles(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  check ((funding_source = 'advanced' and funder_id is not null) or funding_source = 'company')
);

create table if not exists public.procurement_items (
  id uuid primary key default gen_random_uuid(),
  procurement_id uuid not null references public.procurements(id) on delete cascade,
  variant_id uuid not null references public.item_variants(id),
  ordered_quantity numeric(14,2) not null check (ordered_quantity > 0),
  received_quantity numeric(14,2) not null default 0 check (received_quantity >= 0),
  unit_price numeric(16,2) not null default 0 check (unit_price >= 0),
  notes text,
  created_at timestamptz not null default now(),
  check (received_quantity <= ordered_quantity)
);

create table if not exists public.procurement_payments (
  id uuid primary key default gen_random_uuid(),
  procurement_id uuid not null references public.procurements(id) on delete restrict,
  paid_at date not null,
  amount numeric(16,2) not null check (amount > 0),
  payment_method public.payment_method not null,
  payment_type text not null default 'full' check (payment_type in ('dp', 'installment', 'full', 'reimbursement')),
  reference_no text,
  proof_key text,
  notes text,
  created_by uuid references public.profiles(id),
  created_at timestamptz not null default now()
);

-- Link receipts (purchases) to procurements
alter table public.purchases add column if not exists procurement_id uuid references public.procurements(id);
alter table public.purchase_items add column if not exists procurement_item_id uuid references public.procurement_items(id);

create index if not exists procurements_status_idx on public.procurements(status, procurement_date desc);
create index if not exists procurement_items_proc_idx on public.procurement_items(procurement_id);
create index if not exists procurement_items_variant_idx on public.procurement_items(variant_id);
create index if not exists purchases_procurement_idx on public.purchases(procurement_id);
create index if not exists procurement_payments_proc_idx on public.procurement_payments(procurement_id);

drop trigger if exists procurements_touch on public.procurements;
create trigger procurements_touch before update on public.procurements for each row execute function public.touch_updated_at();

-- Progress View for Procurements
create or replace view public.procurement_progress_view with (security_invoker = true) as
select
  p.id,
  p.procurement_no,
  p.procurement_date,
  p.expected_date,
  p.pr_number,
  p.po_number,
  p.department_id,
  d.name as department_name,
  p.supplier_id,
  s.name as supplier_name,
  s.code as supplier_code,
  p.reason,
  p.funding_source,
  p.payment_method,
  p.funder_id,
  f.name as funder_name,
  p.total_amount,
  p.paid_amount,
  greatest(p.total_amount - p.paid_amount, 0) as remaining_amount,
  p.payment_status,
  p.reimbursement_status,
  p.status,
  p.document_key,
  p.notes,
  p.created_at,
  coalesce(sum(pi.ordered_quantity), 0) as total_ordered,
  coalesce(sum(pi.received_quantity), 0) as total_received,
  case
    when coalesce(sum(pi.ordered_quantity), 0) = 0 then 0
    else round((coalesce(sum(pi.received_quantity), 0) / sum(pi.ordered_quantity)) * 100)::int
  end as progress_percent,
  coalesce(
    (select sum(pp.amount) from public.procurement_payments pp where pp.procurement_id = p.id and pp.payment_type = 'reimbursement'),
    0
  ) as reimbursed_amount
from public.procurements p
join public.suppliers s on s.id = p.supplier_id
left join public.departments d on d.id = p.department_id
left join public.funders f on f.id = p.funder_id
left join public.procurement_items pi on pi.procurement_id = p.id
group by p.id, d.name, s.name, s.code, f.name;

-- RLS Policies
alter table public.opening_stocks enable row level security;
alter table public.opening_stock_items enable row level security;
alter table public.procurements enable row level security;
alter table public.procurement_items enable row level security;
alter table public.procurement_payments enable row level security;

do $$
declare tbl text;
begin
  foreach tbl in array array['opening_stocks','opening_stock_items','procurements','procurement_items','procurement_payments'] loop
    execute format('drop policy if exists %I on public.%I', tbl || '_read', tbl);
    execute format('create policy %I on public.%I for select to authenticated using (public.current_user_role() is not null)', tbl || '_read', tbl);
  end loop;
end $$;

revoke insert, update, delete on public.opening_stocks, public.opening_stock_items, public.procurements, public.procurement_items, public.procurement_payments from authenticated;
grant select on public.procurement_progress_view to authenticated;

-- RPC: Create Opening Stock (Stok Awal)
create or replace function public.create_opening_stock(p_payload jsonb, p_actor uuid)
returns uuid language plpgsql security definer set search_path = public as $$
declare opening_id uuid;
declare line jsonb;
declare key text := p_payload ->> 'idempotencyKey';
begin
  if key is not null then
    select id into opening_id from public.opening_stocks where idempotency_key = key;
    if opening_id is not null then return opening_id; end if;
  end if;

  insert into public.opening_stocks (transaction_no, recorded_at, officer_name, notes, idempotency_key, created_by)
  values (
    public.next_document_no('SA', 'public.opening_stock_no_seq'),
    (p_payload ->> 'recordedAt')::timestamptz::date,
    p_payload ->> 'officerName',
    nullif(p_payload ->> 'notes', ''),
    key,
    p_actor
  ) returning id into opening_id;

  for line in select * from jsonb_array_elements(p_payload -> 'items') loop
    insert into public.opening_stock_items (opening_stock_id, variant_id, condition, quantity, notes)
    values (
      opening_id,
      (line ->> 'variantId')::uuid,
      (line ->> 'condition')::public.stock_condition,
      (line ->> 'quantity')::numeric,
      nullif(line ->> 'notes', '')
    );

    perform public.apply_stock_movement(
      (line ->> 'variantId')::uuid,
      (line ->> 'condition')::public.stock_condition,
      (line ->> 'quantity')::numeric,
      'opening_stock',
      'opening_stock',
      opening_id,
      p_actor,
      coalesce(nullif(line ->> 'notes', ''), 'Input stok awal sebelumnya'),
      case when (p_payload ->> 'recordedAt')::timestamptz::date = current_date then now() else (p_payload ->> 'recordedAt')::timestamptz end
    );
  end loop;
  return opening_id;
end;
$$;

-- RPC: Create Procurement (Pengadaan Barang)
create or replace function public.create_procurement(p_payload jsonb, p_actor uuid)
returns uuid language plpgsql security definer set search_path = public as $$
declare proc_id uuid;
declare line jsonb;
declare calc_total numeric := 0;
declare payload_total numeric;
declare key text := p_payload ->> 'idempotencyKey';
begin
  if key is not null then
    select id into proc_id from public.procurements where idempotency_key = key;
    if proc_id is not null then return proc_id; end if;
  end if;

  for line in select * from jsonb_array_elements(p_payload -> 'items') loop
    calc_total := calc_total + ((line ->> 'orderedQuantity')::numeric * coalesce((line ->> 'unitPrice')::numeric, 0));
  end loop;

  payload_total := coalesce(nullif(p_payload ->> 'totalAmount', '')::numeric, calc_total);
  if payload_total = 0 and calc_total > 0 then
    payload_total := calc_total;
  end if;

  insert into public.procurements (
    procurement_no, procurement_date, expected_date, pr_number, po_number,
    department_id, supplier_id, reason, funding_source, payment_method,
    funder_id, total_amount, reimbursement_status, status, document_key, notes,
    idempotency_key, created_by
  ) values (
    public.next_document_no('PGD', 'public.procurement_no_seq'),
    (p_payload ->> 'procurementDate')::timestamptz::date,
    nullif(p_payload ->> 'expectedDate', '')::timestamptz::date,
    nullif(p_payload ->> 'prNumber', ''),
    nullif(p_payload ->> 'poNumber', ''),
    nullif(p_payload ->> 'departmentId', '')::uuid,
    (p_payload ->> 'supplierId')::uuid,
    p_payload ->> 'reason',
    (p_payload ->> 'fundingSource')::public.funding_source,
    (p_payload ->> 'paymentMethod')::public.payment_method,
    nullif(p_payload ->> 'funderId', '')::uuid,
    payload_total,
    case when p_payload ->> 'fundingSource' = 'advanced' then 'not_submitted'::public.reimbursement_status else null end,
    'ordered',
    nullif(p_payload ->> 'documentKey', ''),
    nullif(p_payload ->> 'notes', ''),
    key,
    p_actor
  ) returning id into proc_id;

  for line in select * from jsonb_array_elements(p_payload -> 'items') loop
    insert into public.procurement_items (
      procurement_id, variant_id, ordered_quantity, unit_price, notes
    ) values (
      proc_id,
      (line ->> 'variantId')::uuid,
      (line ->> 'orderedQuantity')::numeric,
      coalesce((line ->> 'unitPrice')::numeric, 0),
      nullif(line ->> 'notes', '')
    );
  end loop;

  return proc_id;
end;
$$;

-- Updated RPC: Create Purchase Receipt (Barang Masuk, optionally linked to Procurement)
create or replace function public.create_purchase_receipt(p_payload jsonb, p_actor uuid)
returns uuid language plpgsql security definer set search_path = public as $$
declare purchase_id uuid;
declare proc_id uuid := nullif(p_payload ->> 'procurementId', '')::uuid;
declare proc_row public.procurements%rowtype;
declare proc_item public.procurement_items%rowtype;
declare line jsonb;
declare line_proc_item_id uuid;
declare remaining_qty numeric;
declare total_ord numeric;
declare total_rec numeric;
declare key text := p_payload ->> 'idempotencyKey';
begin
  if key is not null then
    select id into purchase_id from public.purchases where idempotency_key = key;
    if purchase_id is not null then return purchase_id; end if;
  end if;

  if proc_id is not null then
    select * into proc_row from public.procurements where id = proc_id for update;
    if proc_row.id is null then raise exception 'Pengadaan barang tidak ditemukan'; end if;
    if proc_row.status in ('cancelled', 'completed') then
      raise exception 'Pengadaan % sudah berstatus %', proc_row.procurement_no, proc_row.status;
    end if;
  end if;

  insert into public.purchases (
    transaction_no, purchase_date, received_date, pr_number, request_number, po_number,
    delivery_note_number, invoice_number, reason, supplier_id, billing_proof_key,
    payment_proof_key, total_paid, funding_source, payment_method, funder_id,
    reimbursement_status, procurement_id, idempotency_key, created_by
  ) values (
    public.next_document_no('PB', 'public.purchase_no_seq'),
    coalesce(nullif(p_payload ->> 'purchaseDate', '')::timestamptz::date, proc_row.procurement_date, (p_payload ->> 'receivedDate')::timestamptz::date),
    (p_payload ->> 'receivedDate')::timestamptz::date,
    coalesce(nullif(p_payload ->> 'prNumber', ''), proc_row.pr_number),
    nullif(p_payload ->> 'requestNumber', ''),
    coalesce(nullif(p_payload ->> 'poNumber', ''), proc_row.po_number),
    nullif(p_payload ->> 'deliveryNoteNumber', ''),
    nullif(p_payload ->> 'invoiceNumber', ''),
    coalesce(nullif(p_payload ->> 'reason', ''), proc_row.reason, 'Penerimaan barang'),
    coalesce(nullif(p_payload ->> 'supplierId', '')::uuid, proc_row.supplier_id),
    nullif(p_payload ->> 'billingProofKey', ''),
    nullif(p_payload ->> 'paymentProofKey', ''),
    coalesce((p_payload ->> 'totalPaid')::numeric, 0),
    coalesce(nullif(p_payload ->> 'fundingSource', '')::public.funding_source, proc_row.funding_source, 'company'::public.funding_source),
    coalesce(nullif(p_payload ->> 'paymentMethod', '')::public.payment_method, proc_row.payment_method, 'transfer'::public.payment_method),
    coalesce(nullif(p_payload ->> 'funderId', '')::uuid, proc_row.funder_id),
    case when coalesce(p_payload ->> 'fundingSource', proc_row.funding_source::text) = 'advanced' then 'not_submitted'::public.reimbursement_status else null end,
    proc_id,
    key,
    p_actor
  ) returning id into purchase_id;

  for line in select * from jsonb_array_elements(p_payload -> 'items') loop
    line_proc_item_id := nullif(line ->> 'procurementItemId', '')::uuid;

    if line_proc_item_id is not null then
      select * into proc_item from public.procurement_items where id = line_proc_item_id for update;
      if proc_item.id is null then raise exception 'Item pengadaan tidak ditemukan'; end if;
      if proc_id is not null and proc_item.procurement_id <> proc_id then
        raise exception 'Item tidak sesuai dengan pengadaan yang dipilih';
      end if;
      remaining_qty := proc_item.ordered_quantity - proc_item.received_quantity;
      if (line ->> 'quantity')::numeric > remaining_qty then
        raise exception 'Jumlah diterima melebihi sisa pengadaan (% tersisa)', remaining_qty;
      end if;
      update public.procurement_items
      set received_quantity = received_quantity + (line ->> 'quantity')::numeric
      where id = proc_item.id;
    end if;

    insert into public.purchase_items (
      purchase_id, variant_id, quantity, condition, serial_number, receiver_name, receipt_proof_key, notes, procurement_item_id
    ) values (
      purchase_id, (line ->> 'variantId')::uuid, (line ->> 'quantity')::numeric,
      (line ->> 'condition')::public.stock_condition, nullif(line ->> 'serialNumber', ''),
      line ->> 'receiverName', nullif(line ->> 'receiptProofKey', ''), nullif(line ->> 'notes', ''),
      line_proc_item_id
    );

    perform public.apply_stock_movement(
      (line ->> 'variantId')::uuid,
      (line ->> 'condition')::public.stock_condition,
      (line ->> 'quantity')::numeric,
      'receipt',
      'purchase',
      purchase_id,
      p_actor,
      coalesce(nullif(line ->> 'notes', ''), case when proc_id is not null then 'Penerimaan ' || proc_row.procurement_no else 'Penerimaan pembelian' end),
      case when (p_payload ->> 'receivedDate')::timestamptz::date = current_date then now() else (p_payload ->> 'receivedDate')::timestamptz end
    );
  end loop;

  if proc_id is not null then
    select coalesce(sum(ordered_quantity), 0), coalesce(sum(received_quantity), 0)
    into total_ord, total_rec
    from public.procurement_items where procurement_id = proc_id;

    update public.procurements
    set status = case
      when total_rec >= total_ord and total_ord > 0 then 'completed'
      when total_rec > 0 then 'partial'
      else 'ordered'
    end
    where id = proc_id;
  end if;

  return purchase_id;
end;
$$;

-- RPC: Record Procurement Payment / Reimbursement
create or replace function public.create_procurement_payment(p_payload jsonb, p_actor uuid)
returns uuid language plpgsql security definer set search_path = public as $$
declare payment_id uuid;
declare proc_row public.procurements%rowtype;
declare pay_type text := coalesce(p_payload ->> 'paymentType', 'full');
declare req_amount numeric := (p_payload ->> 'amount')::numeric;
declare already_reimbursed numeric;
declare remaining numeric;
begin
  select * into proc_row from public.procurements where id = (p_payload ->> 'procurementId')::uuid for update;
  if proc_row.id is null then raise exception 'Pengadaan tidak ditemukan'; end if;

  if pay_type = 'reimbursement' then
    if proc_row.funding_source <> 'advanced' then
      raise exception 'Reimbursement hanya berlaku untuk pengadaan dengan dana talangan';
    end if;
    select coalesce(sum(amount), 0) into already_reimbursed
    from public.procurement_payments where procurement_id = proc_row.id and payment_type = 'reimbursement';
    remaining := proc_row.total_amount - already_reimbursed;
    if req_amount > remaining then
      raise exception 'Jumlah reimbursement melebihi sisa %', remaining;
    end if;
  else
    remaining := proc_row.total_amount - proc_row.paid_amount;
    if req_amount > remaining then
      raise exception 'Jumlah pembayaran melebihi sisa tagihan %', remaining;
    end if;
  end if;

  insert into public.procurement_payments (
    procurement_id, paid_at, amount, payment_method, payment_type, reference_no, proof_key, notes, created_by
  ) values (
    proc_row.id,
    (p_payload ->> 'paidAt')::timestamptz::date,
    req_amount,
    (p_payload ->> 'paymentMethod')::public.payment_method,
    pay_type,
    nullif(p_payload ->> 'referenceNo', ''),
    nullif(p_payload ->> 'proofKey', ''),
    nullif(p_payload ->> 'notes', ''),
    p_actor
  ) returning id into payment_id;

  if pay_type = 'reimbursement' then
    update public.procurements
    set reimbursement_status = case
      when req_amount = remaining then 'paid'::public.reimbursement_status
      else 'partially_paid'::public.reimbursement_status
    end
    where id = proc_row.id;
  else
    update public.procurements
    set paid_amount = paid_amount + req_amount,
        payment_status = case
          when paid_amount + req_amount >= total_amount then 'paid'
          else 'partial'
        end
    where id = proc_row.id;
  end if;

  return payment_id;
end;
$$;

-- RPC: Transfer Stock Condition (e.g. quarantine -> used_good or damaged)
create or replace function public.transfer_stock_condition(p_payload jsonb, p_actor uuid)
returns uuid language plpgsql security definer set search_path = public as $$
declare v_variant uuid := (p_payload ->> 'variantId')::uuid;
declare v_from public.stock_condition := (p_payload ->> 'fromCondition')::public.stock_condition;
declare v_to public.stock_condition := (p_payload ->> 'toCondition')::public.stock_condition;
declare v_qty numeric := (p_payload ->> 'quantity')::numeric;
declare v_ref uuid := gen_random_uuid();
begin
  if v_from = v_to then raise exception 'Kondisi asal dan tujuan tidak boleh sama'; end if;
  perform public.apply_stock_movement(v_variant, v_from, -v_qty, 'condition_transfer', 'condition_transfer', v_ref, p_actor, coalesce(nullif(p_payload ->> 'notes', ''), 'Pemindahan kondisi stok'), now());
  perform public.apply_stock_movement(v_variant, v_to, v_qty, 'condition_transfer', 'condition_transfer', v_ref, p_actor, coalesce(nullif(p_payload ->> 'notes', ''), 'Pemindahan kondisi stok'), now());
  return v_ref;
end;
$$;

-- RPC: Create Stocktake (with optional immediate finalization)
create or replace function public.create_stocktake(p_payload jsonb, p_actor uuid)
returns uuid language plpgsql security definer set search_path = public as $$
declare st_id uuid;
declare line jsonb;
declare sys_qty numeric;
declare ref_ts timestamptz := coalesce(nullif(p_payload ->> 'referenceAt', '')::timestamptz, now());
declare finalize_now boolean := coalesce((p_payload ->> 'finalizeNow')::boolean, false);
begin
  insert into public.stocktakes (stocktake_no, reference_at, officer_name, status, submitted_at, created_by)
  values (
    public.next_document_no('SO', 'public.stocktake_no_seq'),
    ref_ts,
    p_payload ->> 'officerName',
    'pending_review',
    now(),
    p_actor
  ) returning id into st_id;

  for line in select * from jsonb_array_elements(p_payload -> 'items') loop
    select coalesce(quantity, 0) into sys_qty
    from public.stock_balances
    where variant_id = (line ->> 'variantId')::uuid
      and condition = (line ->> 'condition')::public.stock_condition;
    sys_qty := coalesce(sys_qty, 0);

    insert into public.stocktake_items (
      stocktake_id, variant_id, condition, system_quantity, physical_quantity, reason, adjustment_quantity
    ) values (
      st_id,
      (line ->> 'variantId')::uuid,
      (line ->> 'condition')::public.stock_condition,
      sys_qty,
      (line ->> 'physicalQuantity')::numeric,
      nullif(line ->> 'reason', ''),
      (line ->> 'physicalQuantity')::numeric - sys_qty
    );
  end loop;

  if finalize_now then
    perform public.finalize_stocktake(st_id, p_actor);
  end if;

  return st_id;
end;
$$;

revoke execute on function public.create_opening_stock(jsonb, uuid) from public, authenticated;
revoke execute on function public.create_procurement(jsonb, uuid) from public, authenticated;
revoke execute on function public.create_procurement_payment(jsonb, uuid) from public, authenticated;
revoke execute on function public.transfer_stock_condition(jsonb, uuid) from public, authenticated;
revoke execute on function public.create_stocktake(jsonb, uuid) from public, authenticated;


-- ===========================================================
-- MIGRATION: 202611190002_edit_transactions.sql
-- ===========================================================
-- Migration: Edit/Update RPCs for Opening Stock, Procurements, Receipts, Issuances, Returns, Stocktakes & Payments

-- 1. Update Opening Stock (Net delta per variant + condition)
create or replace function public.update_opening_stock(p_id uuid, p_payload jsonb, p_actor uuid)
returns uuid language plpgsql security definer set search_path = public as $$
declare delta_row record;
declare line jsonb;
declare old_items jsonb;
begin
  if not exists (select 1 from public.opening_stocks where id = p_id) then
    raise exception 'Data stok awal tidak ditemukan';
  end if;

  select coalesce(jsonb_agg(jsonb_build_object('variantId', variant_id, 'condition', condition, 'quantity', quantity)), '[]'::jsonb)
  into old_items from public.opening_stock_items where opening_stock_id = p_id;

  delete from public.opening_stock_items where opening_stock_id = p_id;

  update public.opening_stocks
  set recorded_at = (p_payload ->> 'recordedAt')::timestamptz::date,
      officer_name = p_payload ->> 'officerName',
      notes = nullif(p_payload ->> 'notes', '')
  where id = p_id;

  for line in select * from jsonb_array_elements(p_payload -> 'items') loop
    insert into public.opening_stock_items (opening_stock_id, variant_id, condition, quantity, notes)
    values (p_id, (line ->> 'variantId')::uuid, (line ->> 'condition')::public.stock_condition, (line ->> 'quantity')::numeric, nullif(line ->> 'notes', ''));
  end loop;

  for delta_row in
    select variant_id, condition, sum(qty) as net_delta
    from (
      select (e ->> 'variantId')::uuid as variant_id, (e ->> 'condition')::public.stock_condition as condition, -(e ->> 'quantity')::numeric as qty
      from jsonb_array_elements(old_items) e
      union all
      select (e ->> 'variantId')::uuid as variant_id, (e ->> 'condition')::public.stock_condition as condition, (e ->> 'quantity')::numeric as qty
      from jsonb_array_elements(p_payload -> 'items') e
    ) t
    group by variant_id, condition
    having sum(qty) <> 0
  loop
    perform public.apply_stock_movement(
      delta_row.variant_id, delta_row.condition, delta_row.net_delta,
      'opening_stock', 'opening_stock', p_id, p_actor, 'Revisi stok awal',
      case when (p_payload ->> 'recordedAt')::timestamptz::date = current_date then now() else (p_payload ->> 'recordedAt')::timestamptz end
    );
  end loop;
  return p_id;
end;
$$;

-- 2. Update Procurement
create or replace function public.update_procurement(p_id uuid, p_payload jsonb, p_actor uuid)
returns uuid language plpgsql security definer set search_path = public as $$
declare proc_row public.procurements%rowtype;
declare line jsonb;
declare line_id uuid;
declare existing_item public.procurement_items%rowtype;
declare calc_total numeric := 0;
declare payload_total numeric;
declare total_ord numeric;
declare total_rec numeric;
declare kept_ids uuid[] := '{}';
begin
  select * into proc_row from public.procurements where id = p_id for update;
  if proc_row.id is null then raise exception 'Pengadaan tidak ditemukan'; end if;
  if proc_row.status = 'cancelled' then raise exception 'Pengadaan yang dibatalkan tidak dapat diedit'; end if;

  for line in select * from jsonb_array_elements(p_payload -> 'items') loop
    calc_total := calc_total + ((line ->> 'orderedQuantity')::numeric * coalesce((line ->> 'unitPrice')::numeric, 0));
  end loop;
  payload_total := coalesce(nullif(p_payload ->> 'totalAmount', '')::numeric, calc_total);
  if payload_total = 0 and calc_total > 0 then payload_total := calc_total; end if;

  if payload_total < proc_row.paid_amount then
    raise exception 'Total pengadaan tidak boleh lebih kecil dari jumlah yang sudah dibayar (%)', proc_row.paid_amount;
  end if;

  for line in select * from jsonb_array_elements(p_payload -> 'items') loop
    line_id := nullif(line ->> 'id', '')::uuid;
    if line_id is not null then
      select * into existing_item from public.procurement_items where id = line_id and procurement_id = p_id for update;
      if existing_item.id is not null then
        if (line ->> 'orderedQuantity')::numeric < existing_item.received_quantity then
          raise exception 'Jumlah dipesan tidak boleh kurang dari yang sudah diterima (%)', existing_item.received_quantity;
        end if;
        update public.procurement_items
        set variant_id = (line ->> 'variantId')::uuid,
            ordered_quantity = (line ->> 'orderedQuantity')::numeric,
            unit_price = coalesce((line ->> 'unitPrice')::numeric, 0),
            notes = nullif(line ->> 'notes', '')
        where id = line_id;
        kept_ids := array_append(kept_ids, line_id);
        continue;
      end if;
    end if;

    insert into public.procurement_items (procurement_id, variant_id, ordered_quantity, unit_price, notes)
    values (p_id, (line ->> 'variantId')::uuid, (line ->> 'orderedQuantity')::numeric, coalesce((line ->> 'unitPrice')::numeric, 0), nullif(line ->> 'notes', ''))
    returning id into line_id;
    kept_ids := array_append(kept_ids, line_id);
  end loop;

  if exists (select 1 from public.procurement_items where procurement_id = p_id and not (id = any(kept_ids)) and received_quantity > 0) then
    raise exception 'Item pengadaan yang sudah memiliki penerimaan barang tidak dapat dihapus';
  end if;
  delete from public.procurement_items where procurement_id = p_id and not (id = any(kept_ids));

  select coalesce(sum(ordered_quantity), 0), coalesce(sum(received_quantity), 0)
  into total_ord, total_rec from public.procurement_items where procurement_id = p_id;

  update public.procurements
  set procurement_date = (p_payload ->> 'procurementDate')::timestamptz::date,
      expected_date = nullif(p_payload ->> 'expectedDate', '')::timestamptz::date,
      pr_number = nullif(p_payload ->> 'prNumber', ''),
      po_number = nullif(p_payload ->> 'poNumber', ''),
      department_id = nullif(p_payload ->> 'departmentId', '')::uuid,
      supplier_id = (p_payload ->> 'supplierId')::uuid,
      reason = p_payload ->> 'reason',
      funding_source = (p_payload ->> 'fundingSource')::public.funding_source,
      payment_method = (p_payload ->> 'paymentMethod')::public.payment_method,
      funder_id = nullif(p_payload ->> 'funderId', '')::uuid,
      total_amount = payload_total,
      payment_status = case when paid_amount >= payload_total and payload_total > 0 then 'paid' when paid_amount > 0 then 'partial' else 'unpaid' end,
      status = case when total_rec >= total_ord and total_ord > 0 then 'completed' when total_rec > 0 then 'partial' else 'ordered' end,
      notes = nullif(p_payload ->> 'notes', '')
  where id = p_id;

  return p_id;
end;
$$;

-- 3. Update Purchase Receipt (Net delta per variant + condition)
create or replace function public.update_purchase_receipt(p_id uuid, p_payload jsonb, p_actor uuid)
returns uuid language plpgsql security definer set search_path = public as $$
declare pur_row public.purchases%rowtype;
declare old_line record;
declare old_items jsonb;
declare delta_row record;
declare line jsonb;
declare proc_id uuid := nullif(p_payload ->> 'procurementId', '')::uuid;
declare line_proc_item_id uuid;
declare proc_item public.procurement_items%rowtype;
declare remaining_qty numeric;
declare total_ord numeric;
declare total_rec numeric;
begin
  select * into pur_row from public.purchases where id = p_id for update;
  if pur_row.id is null then raise exception 'Transaksi barang masuk tidak ditemukan'; end if;

  select coalesce(jsonb_agg(jsonb_build_object('variantId', variant_id, 'condition', condition, 'quantity', quantity)), '[]'::jsonb)
  into old_items from public.purchase_items where purchase_id = p_id;

  for old_line in select * from public.purchase_items where purchase_id = p_id loop
    if old_line.procurement_item_id is not null then
      update public.procurement_items
      set received_quantity = greatest(0, received_quantity - old_line.quantity)
      where id = old_line.procurement_item_id;
    end if;
  end loop;

  delete from public.purchase_items where purchase_id = p_id;

  if pur_row.procurement_id is not null and (proc_id is null or proc_id <> pur_row.procurement_id) then
    select coalesce(sum(ordered_quantity), 0), coalesce(sum(received_quantity), 0)
    into total_ord, total_rec from public.procurement_items where procurement_id = pur_row.procurement_id;
    update public.procurements
    set status = case when total_rec >= total_ord and total_ord > 0 then 'completed' when total_rec > 0 then 'partial' else 'ordered' end
    where id = pur_row.procurement_id;
  end if;

  update public.purchases
  set procurement_id = proc_id,
      received_date = (p_payload ->> 'receivedDate')::timestamptz::date,
      supplier_id = coalesce(nullif(p_payload ->> 'supplierId', '')::uuid, supplier_id),
      reason = coalesce(nullif(p_payload ->> 'reason', ''), reason),
      billing_proof_key = coalesce(nullif(p_payload ->> 'billingProofKey', ''), billing_proof_key)
  where id = p_id;

  for line in select * from jsonb_array_elements(p_payload -> 'items') loop
    line_proc_item_id := nullif(line ->> 'procurementItemId', '')::uuid;
    if line_proc_item_id is not null then
      select * into proc_item from public.procurement_items where id = line_proc_item_id for update;
      remaining_qty := proc_item.ordered_quantity - proc_item.received_quantity;
      if (line ->> 'quantity')::numeric > remaining_qty then
        raise exception 'Jumlah diterima melebihi sisa pengadaan (% tersisa)', remaining_qty;
      end if;
      update public.procurement_items set received_quantity = received_quantity + (line ->> 'quantity')::numeric where id = proc_item.id;
    end if;

    insert into public.purchase_items (purchase_id, variant_id, quantity, condition, receiver_name, notes, procurement_item_id)
    values (p_id, (line ->> 'variantId')::uuid, (line ->> 'quantity')::numeric, (line ->> 'condition')::public.stock_condition, line ->> 'receiverName', nullif(line ->> 'notes', ''), line_proc_item_id);
  end loop;

  for delta_row in
    select variant_id, condition, sum(qty) as net_delta
    from (
      select (e ->> 'variantId')::uuid as variant_id, (e ->> 'condition')::public.stock_condition as condition, -(e ->> 'quantity')::numeric as qty
      from jsonb_array_elements(old_items) e
      union all
      select (e ->> 'variantId')::uuid as variant_id, (e ->> 'condition')::public.stock_condition as condition, (e ->> 'quantity')::numeric as qty
      from jsonb_array_elements(p_payload -> 'items') e
    ) t
    group by variant_id, condition
    having sum(qty) <> 0
  loop
    perform public.apply_stock_movement(
      delta_row.variant_id, delta_row.condition, delta_row.net_delta,
      'receipt', 'purchase', p_id, p_actor, 'Revisi barang masuk',
      case when (p_payload ->> 'receivedDate')::timestamptz::date = current_date then now() else (p_payload ->> 'receivedDate')::timestamptz end
    );
  end loop;

  if proc_id is not null then
    select coalesce(sum(ordered_quantity), 0), coalesce(sum(received_quantity), 0)
    into total_ord, total_rec from public.procurement_items where procurement_id = proc_id;
    update public.procurements
    set status = case when total_rec >= total_ord and total_ord > 0 then 'completed' when total_rec > 0 then 'partial' else 'ordered' end
    where id = proc_id;
  end if;

  return p_id;
end;
$$;

-- 4. Update Issuance (Barang Keluar)
create or replace function public.update_issuance(p_id uuid, p_payload jsonb, p_actor uuid)
returns uuid language plpgsql security definer set search_path = public as $$
declare old_line record;
declare line jsonb;
declare v_condition public.stock_condition;
begin
  if not exists (select 1 from public.issuances where id = p_id) then
    raise exception 'Transaksi barang keluar tidak ditemukan';
  end if;

  if exists (select 1 from public.issuance_items where issuance_id = p_id and (returned_quantity > 0 or resolved_lost_quantity > 0)) then
    raise exception 'Barang keluar yang sudah memiliki catatan pengembalian tidak dapat diubah itemnya';
  end if;

  for old_line in select * from public.issuance_items where issuance_id = p_id loop
    perform public.apply_stock_movement(
      old_line.variant_id, old_line.condition, old_line.quantity,
      'issuance', 'issuance', p_id, p_actor, 'Revisi barang keluar (koreksi)', now()
    );
  end loop;

  delete from public.issuance_items where issuance_id = p_id;

  update public.issuances
  set issued_at = (p_payload ->> 'issuedAt')::timestamptz::date,
      employee_id = (p_payload ->> 'employeeId')::uuid,
      officer_name = p_payload ->> 'officerName',
      handover_proof_key = coalesce(nullif(p_payload ->> 'handoverProofKey', ''), handover_proof_key),
      notes = nullif(p_payload ->> 'notes', '')
  where id = p_id;

  for line in select * from jsonb_array_elements(p_payload -> 'items') loop
    v_condition := (line ->> 'condition')::public.stock_condition;
    insert into public.issuance_items (issuance_id, variant_id, condition, quantity, purpose, notes)
    values (p_id, (line ->> 'variantId')::uuid, v_condition, (line ->> 'quantity')::numeric, line ->> 'purpose', nullif(line ->> 'notes', ''));

    perform public.apply_stock_movement(
      (line ->> 'variantId')::uuid, v_condition, -(line ->> 'quantity')::numeric,
      'issuance', 'issuance', p_id, p_actor, line ->> 'purpose',
      case when (p_payload ->> 'issuedAt')::timestamptz::date = current_date then now() else (p_payload ->> 'issuedAt')::timestamptz end
    );
  end loop;
  return p_id;
end;
$$;

-- 5. Update Return APD
create or replace function public.update_return(p_id uuid, p_payload jsonb, p_actor uuid)
returns uuid language plpgsql security definer set search_path = public as $$
declare old_line record;
declare issue_line public.issuance_items%rowtype;
declare line jsonb;
declare remaining numeric;
declare result public.inspection_result;
declare target_condition public.stock_condition;
begin
  if not exists (select 1 from public.returns where id = p_id) then
    raise exception 'Transaksi pengembalian tidak ditemukan';
  end if;

  for old_line in select * from public.return_items where return_id = p_id loop
    select * into issue_line from public.issuance_items where id = old_line.issuance_item_id for update;
    if old_line.result = 'lost' then
      update public.issuance_items set resolved_lost_quantity = greatest(0, resolved_lost_quantity - old_line.quantity) where id = issue_line.id;
    else
      update public.issuance_items set returned_quantity = greatest(0, returned_quantity - old_line.quantity) where id = issue_line.id;
      target_condition := case old_line.result when 'used_good' then 'used_good'::public.stock_condition when 'maintenance' then 'quarantine'::public.stock_condition when 'damaged' then 'damaged'::public.stock_condition end;
      perform public.apply_stock_movement(issue_line.variant_id, target_condition, -old_line.quantity, 'return', 'return', p_id, p_actor, 'Revisi pengembalian (koreksi)', now());
    end if;
  end loop;

  delete from public.return_items where return_id = p_id;

  update public.returns
  set returned_at = (p_payload ->> 'returnedAt')::timestamptz::date,
      employee_id = (p_payload ->> 'employeeId')::uuid,
      inspector_name = p_payload ->> 'inspectorName',
      proof_key = coalesce(nullif(p_payload ->> 'proofKey', ''), proof_key)
  where id = p_id;

  for line in select * from jsonb_array_elements(p_payload -> 'items') loop
    select * into issue_line from public.issuance_items where id = (line ->> 'issuanceItemId')::uuid for update;
    remaining := issue_line.quantity - issue_line.returned_quantity - issue_line.resolved_lost_quantity;
    if (line ->> 'quantity')::numeric > remaining then
      raise exception 'Jumlah pengembalian melebihi sisa tanggungan %', remaining;
    end if;
    result := (line ->> 'inspectionResult')::public.inspection_result;
    insert into public.return_items (return_id, issuance_item_id, quantity, result, reason, notes)
    values (p_id, issue_line.id, (line ->> 'quantity')::numeric, result, nullif(line ->> 'reason', ''), nullif(line ->> 'notes', ''));

    if result = 'lost' then
      update public.issuance_items set resolved_lost_quantity = resolved_lost_quantity + (line ->> 'quantity')::numeric where id = issue_line.id;
    else
      update public.issuance_items set returned_quantity = returned_quantity + (line ->> 'quantity')::numeric where id = issue_line.id;
      target_condition := case result when 'used_good' then 'used_good'::public.stock_condition when 'maintenance' then 'quarantine'::public.stock_condition when 'damaged' then 'damaged'::public.stock_condition end;
      perform public.apply_stock_movement(
        issue_line.variant_id, target_condition, (line ->> 'quantity')::numeric,
        'return', 'return', p_id, p_actor, coalesce(line ->> 'reason', 'Revisi pengembalian APD'),
        case when (p_payload ->> 'returnedAt')::timestamptz::date = current_date then now() else (p_payload ->> 'returnedAt')::timestamptz end
      );
    end if;
  end loop;
  return p_id;
end;
$$;

-- 6. Update Stocktake (while pending_review / draft)
create or replace function public.update_stocktake(p_id uuid, p_payload jsonb, p_actor uuid)
returns uuid language plpgsql security definer set search_path = public as $$
declare st_row public.stocktakes%rowtype;
declare line jsonb;
declare sys_qty numeric;
declare finalize_now boolean := coalesce((p_payload ->> 'finalizeNow')::boolean, false);
begin
  select * into st_row from public.stocktakes where id = p_id for update;
  if st_row.id is null then raise exception 'Stok opname tidak ditemukan'; end if;
  if st_row.status = 'completed' then raise exception 'Stok opname yang sudah difinalisasi tidak dapat diedit'; end if;

  update public.stocktakes
  set officer_name = p_payload ->> 'officerName',
      reference_at = coalesce(nullif(p_payload ->> 'referenceAt', '')::timestamptz, reference_at)
  where id = p_id;

  delete from public.stocktake_items where stocktake_id = p_id;

  for line in select * from jsonb_array_elements(p_payload -> 'items') loop
    select coalesce(quantity, 0) into sys_qty from public.stock_balances
    where variant_id = (line ->> 'variantId')::uuid and condition = (line ->> 'condition')::public.stock_condition;
    sys_qty := coalesce(sys_qty, 0);

    insert into public.stocktake_items (stocktake_id, variant_id, condition, system_quantity, physical_quantity, reason, adjustment_quantity)
    values (p_id, (line ->> 'variantId')::uuid, (line ->> 'condition')::public.stock_condition, sys_qty, (line ->> 'physicalQuantity')::numeric, nullif(line ->> 'reason', ''), (line ->> 'physicalQuantity')::numeric - sys_qty);
  end loop;

  if finalize_now then
    perform public.finalize_stocktake(p_id, p_actor);
  end if;
  return p_id;
end;
$$;

-- 7. Update Procurement Payment
create or replace function public.update_procurement_payment(p_id uuid, p_payload jsonb, p_actor uuid)
returns uuid language plpgsql security definer set search_path = public as $$
declare old_pay public.procurement_payments%rowtype;
declare proc_row public.procurements%rowtype;
declare req_amount numeric := (p_payload ->> 'amount')::numeric;
declare pay_type text := coalesce(p_payload ->> 'paymentType', 'full');
declare new_paid numeric;
declare new_reimb numeric;
begin
  select * into old_pay from public.procurement_payments where id = p_id for update;
  if old_pay.id is null then raise exception 'Data pembayaran tidak ditemukan'; end if;

  select * into proc_row from public.procurements where id = old_pay.procurement_id for update;

  update public.procurement_payments
  set paid_at = (p_payload ->> 'paidAt')::timestamptz::date,
      amount = req_amount,
      payment_method = (p_payload ->> 'paymentMethod')::public.payment_method,
      payment_type = pay_type,
      reference_no = nullif(p_payload ->> 'referenceNo', ''),
      proof_key = coalesce(nullif(p_payload ->> 'proofKey', ''), proof_key),
      notes = nullif(p_payload ->> 'notes', '')
  where id = p_id;

  select coalesce(sum(amount), 0) into new_paid from public.procurement_payments where procurement_id = proc_row.id and payment_type <> 'reimbursement';
  if new_paid > proc_row.total_amount then
    raise exception 'Total pembayaran (%) melebihi total tagihan (%)', new_paid, proc_row.total_amount;
  end if;

  select coalesce(sum(amount), 0) into new_reimb from public.procurement_payments where procurement_id = proc_row.id and payment_type = 'reimbursement';
  if proc_row.funding_source = 'advanced' and new_reimb > proc_row.total_amount then
    raise exception 'Total reimbursement melebihi nilai pengadaan';
  end if;

  update public.procurements
  set paid_amount = new_paid,
      payment_status = case when new_paid >= total_amount and total_amount > 0 then 'paid' when new_paid > 0 then 'partial' else 'unpaid' end,
      reimbursement_status = case when funding_source = 'advanced' then (case when new_reimb >= total_amount then 'paid'::public.reimbursement_status when new_reimb > 0 then 'partially_paid'::public.reimbursement_status else 'not_submitted'::public.reimbursement_status end) else null end
  where id = proc_row.id;

  return p_id;
end;
$$;

revoke execute on function public.update_opening_stock(uuid, jsonb, uuid) from public, authenticated;
revoke execute on function public.update_procurement(uuid, jsonb, uuid) from public, authenticated;
revoke execute on function public.update_purchase_receipt(uuid, jsonb, uuid) from public, authenticated;
revoke execute on function public.update_issuance(uuid, jsonb, uuid) from public, authenticated;
revoke execute on function public.update_return(uuid, jsonb, uuid) from public, authenticated;
revoke execute on function public.update_stocktake(uuid, jsonb, uuid) from public, authenticated;
revoke execute on function public.update_procurement_payment(uuid, jsonb, uuid) from public, authenticated;


-- ===========================================================
-- MIGRATION: 202611190003_online_shop_and_return_reusable.sql
-- ===========================================================
-- Migration: Vendor Type (Supplier vs Toko Online) & Return Reusable Flag

alter table public.suppliers add column if not exists vendor_type text not null default 'supplier';
alter table public.suppliers drop constraint if exists suppliers_vendor_type_check;
alter table public.suppliers add constraint suppliers_vendor_type_check check (vendor_type in ('supplier', 'online_shop'));

alter table public.return_items add column if not exists reusable boolean not null default false;

drop view if exists public.procurement_progress_view cascade;

create view public.procurement_progress_view with (security_invoker = true) as
select
  p.id,
  p.procurement_no,
  p.procurement_date,
  p.expected_date,
  p.pr_number,
  p.po_number,
  p.department_id,
  d.name as department_name,
  p.supplier_id,
  s.name as supplier_name,
  s.code as supplier_code,
  s.vendor_type,
  p.reason,
  p.funding_source,
  p.payment_method,
  p.funder_id,
  f.name as funder_name,
  p.total_amount,
  p.paid_amount,
  greatest(p.total_amount - p.paid_amount, 0) as remaining_amount,
  p.payment_status,
  p.reimbursement_status,
  p.status,
  p.document_key,
  p.notes,
  p.created_at,
  coalesce(sum(pi.ordered_quantity), 0) as total_ordered,
  coalesce(sum(pi.received_quantity), 0) as total_received,
  case
    when coalesce(sum(pi.ordered_quantity), 0) = 0 then 0
    else round((coalesce(sum(pi.received_quantity), 0) / sum(pi.ordered_quantity)) * 100)::int
  end as progress_percent,
  coalesce(
    (select sum(pp.amount) from public.procurement_payments pp where pp.procurement_id = p.id and pp.payment_type = 'reimbursement'),
    0
  ) as reimbursed_amount
from public.procurements p
join public.suppliers s on s.id = p.supplier_id
left join public.departments d on d.id = p.department_id
left join public.funders f on f.id = p.funder_id
left join public.procurement_items pi on pi.procurement_id = p.id
group by p.id, d.name, s.name, s.code, s.vendor_type, f.name;

grant select on public.procurement_progress_view to authenticated;

-- Update create_return to handle damaged + reusable (Ya -> used_good, Tidak -> does not re-enter stock)
create or replace function public.create_return(p_payload jsonb, p_actor uuid)
returns uuid language plpgsql security definer set search_path = public as $$
declare return_id uuid;
declare line jsonb;
declare issue_line public.issuance_items%rowtype;
declare issue_employee uuid;
declare remaining numeric;
declare result public.inspection_result;
declare is_reusable boolean;
declare target_condition public.stock_condition;
declare key text := p_payload ->> 'idempotencyKey';
begin
  if key is not null then
    select id into return_id from public.returns where idempotency_key = key;
    if return_id is not null then return return_id; end if;
  end if;

  insert into public.returns (transaction_no, returned_at, employee_id, inspector_name, proof_key, idempotency_key, created_by)
  values (
    public.next_document_no('PG', 'public.return_no_seq'),
    (p_payload ->> 'returnedAt')::timestamptz::date, (p_payload ->> 'employeeId')::uuid,
    p_payload ->> 'inspectorName', nullif(p_payload ->> 'proofKey', ''), key, p_actor
  ) returning id into return_id;

  for line in select * from jsonb_array_elements(p_payload -> 'items') loop
    select ii.* into issue_line from public.issuance_items ii where ii.id = (line ->> 'issuanceItemId')::uuid for update;
    if issue_line.id is null then raise exception 'Detail pengeluaran tidak ditemukan'; end if;

    select employee_id into issue_employee from public.issuances where id = issue_line.issuance_id;
    if issue_employee <> (p_payload ->> 'employeeId')::uuid then
      raise exception 'Pengeluaran tidak dimiliki karyawan yang dipilih';
    end if;

    remaining := issue_line.quantity - issue_line.returned_quantity - issue_line.resolved_lost_quantity;
    if (line ->> 'quantity')::numeric > remaining then
      raise exception 'Jumlah pengembalian melebihi sisa tanggungan %', remaining;
    end if;

    result := (line ->> 'inspectionResult')::public.inspection_result;
    is_reusable := coalesce((line ->> 'reusable')::boolean, false);

    if result = 'lost' and nullif(line ->> 'reason', '') is null then
      raise exception 'Alasan wajib diisi untuk penyelesaian kehilangan';
    end if;

    insert into public.return_items (return_id, issuance_item_id, quantity, result, reusable, reason, notes)
    values (
      return_id, issue_line.id, (line ->> 'quantity')::numeric, result, is_reusable,
      nullif(line ->> 'reason', ''), nullif(line ->> 'notes', '')
    );

    if result = 'lost' then
      update public.issuance_items
      set resolved_lost_quantity = resolved_lost_quantity + (line ->> 'quantity')::numeric
      where id = issue_line.id;
    else
      update public.issuance_items
      set returned_quantity = returned_quantity + (line ->> 'quantity')::numeric
      where id = issue_line.id;

      if result = 'used_good' then
        target_condition := 'used_good'::public.stock_condition;
      elsif result = 'maintenance' then
        target_condition := 'quarantine'::public.stock_condition;
      elsif result = 'damaged' and is_reusable then
        target_condition := 'used_good'::public.stock_condition;
      else
        target_condition := null;
      end if;

      if target_condition is not null then
        perform public.apply_stock_movement(
          issue_line.variant_id, target_condition, (line ->> 'quantity')::numeric,
          'return', 'return', return_id, p_actor, coalesce(line ->> 'reason', 'Pengembalian APD'),
          case when (p_payload ->> 'returnedAt')::timestamptz::date = current_date then now() else (p_payload ->> 'returnedAt')::timestamptz end
        );
      end if;
    end if;
  end loop;
  return return_id;
end;
$$;

-- Update update_return similarly
create or replace function public.update_return(p_id uuid, p_payload jsonb, p_actor uuid)
returns uuid language plpgsql security definer set search_path = public as $$
declare old_line record;
declare issue_line public.issuance_items%rowtype;
declare line jsonb;
declare remaining numeric;
declare result public.inspection_result;
declare is_reusable boolean;
declare target_condition public.stock_condition;
begin
  if not exists (select 1 from public.returns where id = p_id) then
    raise exception 'Transaksi pengembalian tidak ditemukan';
  end if;

  for old_line in select * from public.return_items where return_id = p_id loop
    select * into issue_line from public.issuance_items where id = old_line.issuance_item_id for update;
    if old_line.result = 'lost' then
      update public.issuance_items set resolved_lost_quantity = greatest(0, resolved_lost_quantity - old_line.quantity) where id = issue_line.id;
    else
      update public.issuance_items set returned_quantity = greatest(0, returned_quantity - old_line.quantity) where id = issue_line.id;
      if old_line.result = 'used_good' then target_condition := 'used_good'::public.stock_condition;
      elsif old_line.result = 'maintenance' then target_condition := 'quarantine'::public.stock_condition;
      elsif old_line.result = 'damaged' and old_line.reusable then target_condition := 'used_good'::public.stock_condition;
      else target_condition := null;
      end if;
      if target_condition is not null then
        perform public.apply_stock_movement(issue_line.variant_id, target_condition, -old_line.quantity, 'return', 'return', p_id, p_actor, 'Revisi pengembalian (koreksi)', now());
      end if;
    end if;
  end loop;

  delete from public.return_items where return_id = p_id;

  update public.returns
  set returned_at = (p_payload ->> 'returnedAt')::timestamptz::date,
      employee_id = (p_payload ->> 'employeeId')::uuid,
      inspector_name = p_payload ->> 'inspectorName',
      proof_key = coalesce(nullif(p_payload ->> 'proofKey', ''), proof_key)
  where id = p_id;

  for line in select * from jsonb_array_elements(p_payload -> 'items') loop
    select * into issue_line from public.issuance_items where id = (line ->> 'issuanceItemId')::uuid for update;
    remaining := issue_line.quantity - issue_line.returned_quantity - issue_line.resolved_lost_quantity;
    if (line ->> 'quantity')::numeric > remaining then
      raise exception 'Jumlah pengembalian melebihi sisa tanggungan %', remaining;
    end if;
    result := (line ->> 'inspectionResult')::public.inspection_result;
    is_reusable := coalesce((line ->> 'reusable')::boolean, false);

    insert into public.return_items (return_id, issuance_item_id, quantity, result, reusable, reason, notes)
    values (p_id, issue_line.id, (line ->> 'quantity')::numeric, result, is_reusable, nullif(line ->> 'reason', ''), nullif(line ->> 'notes', ''));

    if result = 'lost' then
      update public.issuance_items set resolved_lost_quantity = resolved_lost_quantity + (line ->> 'quantity')::numeric where id = issue_line.id;
    else
      update public.issuance_items set returned_quantity = returned_quantity + (line ->> 'quantity')::numeric where id = issue_line.id;
      if result = 'used_good' then target_condition := 'used_good'::public.stock_condition;
      elsif result = 'maintenance' then target_condition := 'quarantine'::public.stock_condition;
      elsif result = 'damaged' and is_reusable then target_condition := 'used_good'::public.stock_condition;
      else target_condition := null;
      end if;
      if target_condition is not null then
        perform public.apply_stock_movement(
          issue_line.variant_id, target_condition, (line ->> 'quantity')::numeric,
          'return', 'return', p_id, p_actor, coalesce(line ->> 'reason', 'Revisi pengembalian APD'),
          case when (p_payload ->> 'returnedAt')::timestamptz::date = current_date then now() else (p_payload ->> 'returnedAt')::timestamptz end
        );
      end if;
    end if;
  end loop;
  return p_id;
end;
$$;


-- ===========================================================
-- MIGRATION: 202611210001_auto_po_and_auto_issuance.sql
-- ===========================================================
-- Auto-generate PO number when omitted & auto-deduct available stock (new -> used_good) on issuance
-- PRASYARAT: Jalankan migrasi secara berurutan dari 202611180001_initial_schema.sql s/d 202611190003 terlebih dahulu,
-- atau jalankan file gabungan supabase/FULL_SETUP_ALL_IN_ONE.sql untuk database Supabase baru.

create sequence if not exists public.po_no_seq start 1;

create or replace function public.create_procurement(p_payload jsonb, p_actor uuid)
returns uuid language plpgsql security definer set search_path = public as $$
declare proc_id uuid;
declare line jsonb;
declare calc_total numeric := 0;
declare payload_total numeric;
declare v_po text;
declare key text := p_payload ->> 'idempotencyKey';
begin
  if key is not null then
    select id into proc_id from public.procurements where idempotency_key = key;
    if proc_id is not null then return proc_id; end if;
  end if;

  for line in select * from jsonb_array_elements(p_payload -> 'items') loop
    calc_total := calc_total + ((line ->> 'orderedQuantity')::numeric * coalesce((line ->> 'unitPrice')::numeric, 0));
  end loop;

  payload_total := coalesce(nullif(p_payload ->> 'totalAmount', '')::numeric, calc_total);
  if payload_total = 0 and calc_total > 0 then
    payload_total := calc_total;
  end if;

  v_po := coalesce(nullif(trim(p_payload ->> 'poNumber'), ''), public.next_document_no('PO', 'public.po_no_seq'));

  insert into public.procurements (
    procurement_no, procurement_date, expected_date, pr_number, po_number,
    department_id, supplier_id, reason, funding_source, payment_method,
    funder_id, total_amount, reimbursement_status, status, document_key, notes,
    idempotency_key, created_by
  ) values (
    public.next_document_no('PGD', 'public.procurement_no_seq'),
    (p_payload ->> 'procurementDate')::timestamptz::date,
    nullif(p_payload ->> 'expectedDate', '')::timestamptz::date,
    nullif(p_payload ->> 'prNumber', ''),
    v_po,
    nullif(p_payload ->> 'departmentId', '')::uuid,
    (p_payload ->> 'supplierId')::uuid,
    p_payload ->> 'reason',
    (p_payload ->> 'fundingSource')::public.funding_source,
    (p_payload ->> 'paymentMethod')::public.payment_method,
    nullif(p_payload ->> 'funderId', '')::uuid,
    payload_total,
    case when p_payload ->> 'fundingSource' = 'advanced' then 'not_submitted'::public.reimbursement_status else null end,
    'ordered',
    nullif(p_payload ->> 'documentKey', ''),
    nullif(p_payload ->> 'notes', ''),
    key,
    p_actor
  ) returning id into proc_id;

  for line in select * from jsonb_array_elements(p_payload -> 'items') loop
    insert into public.procurement_items (
      procurement_id, variant_id, ordered_quantity, unit_price, notes
    ) values (
      proc_id,
      (line ->> 'variantId')::uuid,
      (line ->> 'orderedQuantity')::numeric,
      coalesce((line ->> 'unitPrice')::numeric, 0),
      nullif(line ->> 'notes', '')
    );
  end loop;

  return proc_id;
end;
$$;

create or replace function public.allocate_issuance_line(
  p_issuance_id uuid,
  p_variant_id uuid,
  p_condition text,
  p_qty numeric,
  p_purpose text,
  p_notes text,
  p_occurred_at timestamptz,
  p_actor uuid
)
returns void language plpgsql security definer set search_path = public as $$
declare v_new numeric := 0;
declare v_used numeric := 0;
declare v_take_new numeric := 0;
declare v_take_used numeric := 0;
declare v_cond public.stock_condition;
begin
  if p_condition is null or p_condition = 'auto' then
    select coalesce(max(case when condition = 'new' then quantity else 0 end), 0),
           coalesce(max(case when condition = 'used_good' then quantity else 0 end), 0)
      into v_new, v_used
      from public.stock_balances
      where variant_id = p_variant_id and condition in ('new', 'used_good');

    if (v_new + v_used) < p_qty then
      raise exception 'Stok tersedia tidak mencukupi (tersedia %)', (v_new + v_used);
    end if;

    v_take_new := least(v_new, p_qty);
    v_take_used := p_qty - v_take_new;

    if v_take_new > 0 then
      insert into public.issuance_items (issuance_id, variant_id, condition, quantity, purpose, notes)
      values (p_issuance_id, p_variant_id, 'new', v_take_new, p_purpose, nullif(p_notes, ''));
      perform public.apply_stock_movement(p_variant_id, 'new', -v_take_new, 'issuance', 'issuance', p_issuance_id, p_actor, p_purpose, p_occurred_at);
    end if;

    if v_take_used > 0 then
      insert into public.issuance_items (issuance_id, variant_id, condition, quantity, purpose, notes)
      values (p_issuance_id, p_variant_id, 'used_good', v_take_used, p_purpose, nullif(p_notes, ''));
      perform public.apply_stock_movement(p_variant_id, 'used_good', -v_take_used, 'issuance', 'issuance', p_issuance_id, p_actor, p_purpose, p_occurred_at);
    end if;
  else
    v_cond := p_condition::public.stock_condition;
    if v_cond not in ('new', 'used_good') then
      raise exception 'Kondisi karantina atau rusak tidak dapat dikeluarkan';
    end if;
    insert into public.issuance_items (issuance_id, variant_id, condition, quantity, purpose, notes)
    values (p_issuance_id, p_variant_id, v_cond, p_qty, p_purpose, nullif(p_notes, ''));
    perform public.apply_stock_movement(p_variant_id, v_cond, -p_qty, 'issuance', 'issuance', p_issuance_id, p_actor, p_purpose, p_occurred_at);
  end if;
end;
$$;

create or replace function public.create_issuance(p_payload jsonb, p_actor uuid)
returns uuid language plpgsql security definer set search_path = public as $$
declare issuance_id uuid;
declare line jsonb;
declare key text := p_payload ->> 'idempotencyKey';
begin
  if key is not null then
    select id into issuance_id from public.issuances where idempotency_key = key;
    if issuance_id is not null then return issuance_id; end if;
  end if;

  insert into public.issuances (
    transaction_no, issued_at, employee_id, officer_name, ba_key, handover_proof_key,
    notes, idempotency_key, created_by
  ) values (
    public.next_document_no('BK', 'public.issuance_no_seq'),
    (p_payload ->> 'issuedAt')::timestamptz::date, (p_payload ->> 'employeeId')::uuid,
    p_payload ->> 'officerName', nullif(p_payload ->> 'baKey', ''),
    nullif(p_payload ->> 'handoverProofKey', ''), nullif(p_payload ->> 'notes', ''), key, p_actor
  ) returning id into issuance_id;

  for line in select * from jsonb_array_elements(p_payload -> 'items') loop
    perform public.allocate_issuance_line(
      issuance_id,
      (line ->> 'variantId')::uuid,
      line ->> 'condition',
      (line ->> 'quantity')::numeric,
      line ->> 'purpose',
      line ->> 'notes',
      (p_payload ->> 'issuedAt')::timestamptz,
      p_actor
    );
  end loop;
  return issuance_id;
end;
$$;

create or replace function public.update_issuance(p_id uuid, p_payload jsonb, p_actor uuid)
returns uuid language plpgsql security definer set search_path = public as $$
declare old_line record;
declare line jsonb;
begin
  if not exists (select 1 from public.issuances where id = p_id) then
    raise exception 'Transaksi barang keluar tidak ditemukan';
  end if;

  if exists (select 1 from public.issuance_items where issuance_id = p_id and (returned_quantity > 0 or resolved_lost_quantity > 0)) then
    raise exception 'Barang keluar yang sudah memiliki catatan pengembalian tidak dapat diubah itemnya';
  end if;

  for old_line in select * from public.issuance_items where issuance_id = p_id loop
    perform public.apply_stock_movement(
      old_line.variant_id, old_line.condition, old_line.quantity,
      'issuance', 'issuance', p_id, p_actor, 'Revisi barang keluar (koreksi)', now()
    );
  end loop;

  delete from public.issuance_items where issuance_id = p_id;

  update public.issuances
  set issued_at = (p_payload ->> 'issuedAt')::timestamptz::date,
      employee_id = (p_payload ->> 'employeeId')::uuid,
      officer_name = p_payload ->> 'officerName',
      handover_proof_key = coalesce(nullif(p_payload ->> 'handoverProofKey', ''), handover_proof_key),
      notes = nullif(p_payload ->> 'notes', '')
  where id = p_id;

  for line in select * from jsonb_array_elements(p_payload -> 'items') loop
    perform public.allocate_issuance_line(
      p_id,
      (line ->> 'variantId')::uuid,
      line ->> 'condition',
      (line ->> 'quantity')::numeric,
      line ->> 'purpose',
      line ->> 'notes',
      case when (p_payload ->> 'issuedAt')::timestamptz::date = current_date then now() else (p_payload ->> 'issuedAt')::timestamptz end,
      p_actor
    );
  end loop;
  return p_id;
end;
$$;

revoke execute on function public.allocate_issuance_line(uuid, uuid, text, numeric, text, text, timestamptz, uuid) from public, authenticated;


-- ===========================================================
-- MIGRATION: 202611210002_optional_category.sql
-- ===========================================================
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
