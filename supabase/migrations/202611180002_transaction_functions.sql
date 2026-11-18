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
