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
