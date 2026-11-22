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
