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
