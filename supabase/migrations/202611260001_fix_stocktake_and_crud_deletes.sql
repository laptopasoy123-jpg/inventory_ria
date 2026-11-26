-- Migration: Fix Stocktake doubling bug (no movement_since double-add), allow editing completed SO,
-- and add atomic DELETE RPCs for full CRUD across all modules.

-- 1. Fix create_stocktake: avoid midnight UTC timestamp trap for today's date
create or replace function public.create_stocktake(p_payload jsonb, p_actor uuid)
returns uuid language plpgsql security definer set search_path = public as $$
declare st_id uuid;
declare line jsonb;
declare sys_qty numeric;
declare raw_ref timestamptz := nullif(p_payload ->> 'referenceAt', '')::timestamptz;
declare ref_ts timestamptz;
declare finalize_now boolean := coalesce((p_payload ->> 'finalizeNow')::boolean, false);
begin
  if raw_ref is null or raw_ref::date = current_date then
    ref_ts := now();
  else
    ref_ts := raw_ref;
  end if;

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

-- 2. Fix finalize_stocktake: reconcile stock_balances directly to physical_quantity (never double-count movements)
create or replace function public.finalize_stocktake(p_stocktake_id uuid, p_actor uuid)
returns uuid language plpgsql security definer set search_path = public as $$
declare stocktake_row public.stocktakes%rowtype;
declare line public.stocktake_items%rowtype;
declare current_qty numeric;
declare adjustment numeric;
begin
  select * into stocktake_row from public.stocktakes where id = p_stocktake_id for update;
  if stocktake_row.id is null then raise exception 'Stok opname tidak ditemukan'; end if;
  if stocktake_row.status <> 'pending_review' then raise exception 'Stok opname harus berstatus Menunggu Pemeriksaan'; end if;
  if stocktake_row.finalized_at is not null then raise exception 'Stok opname sudah pernah difinalisasi'; end if;

  for line in select * from public.stocktake_items where stocktake_id = p_stocktake_id order by variant_id, condition loop
    insert into public.stock_balances (variant_id, condition, quantity)
    values (line.variant_id, line.condition, 0)
    on conflict (variant_id, condition) do nothing;

    select quantity into current_qty from public.stock_balances
    where variant_id = line.variant_id and condition = line.condition for update;

    adjustment := line.physical_quantity - current_qty;

    if adjustment <> 0 then
      perform public.apply_stock_movement(
        line.variant_id, line.condition, adjustment, 'stocktake_adjustment', 'stocktake',
        p_stocktake_id, p_actor, coalesce(line.reason, 'Penyesuaian ' || stocktake_row.stocktake_no), now()
      );
    end if;

    update public.stocktake_items
    set system_quantity = current_qty,
        adjustment_quantity = adjustment
    where id = line.id;
  end loop;

  update public.stocktakes
  set status = 'completed', finalized_at = now(), finalized_by = p_actor
  where id = p_stocktake_id;
  return p_stocktake_id;
end;
$$;

-- 3. Update stocktake: allow editing both draft/pending AND completed stocktakes cleanly
create or replace function public.update_stocktake(p_id uuid, p_payload jsonb, p_actor uuid)
returns uuid language plpgsql security definer set search_path = public as $$
declare st_row public.stocktakes%rowtype;
declare old_line record;
declare line jsonb;
declare sys_qty numeric;
declare adjustment numeric;
declare was_completed boolean;
declare finalize_now boolean := coalesce((p_payload ->> 'finalizeNow')::boolean, false);
declare raw_ref timestamptz := nullif(p_payload ->> 'referenceAt', '')::timestamptz;
declare ref_ts timestamptz;
begin
  select * into st_row from public.stocktakes where id = p_id for update;
  if st_row.id is null then raise exception 'Stok opname tidak ditemukan'; end if;

  was_completed := (st_row.status = 'completed');

  if raw_ref is null then
    ref_ts := st_row.reference_at;
  elsif raw_ref::date = current_date then
    ref_ts := now();
  else
    ref_ts := raw_ref;
  end if;

  -- If already finalized, reverse previous adjustments first
  if was_completed then
    for old_line in select * from public.stocktake_items where stocktake_id = p_id loop
      if coalesce(old_line.adjustment_quantity, 0) <> 0 then
        perform public.apply_stock_movement(
          old_line.variant_id, old_line.condition, -old_line.adjustment_quantity,
          'stocktake_adjustment', 'stocktake', p_id, p_actor,
          'Revisi ' || st_row.stocktake_no || ' (koreksi)', now()
        );
      end if;
    end loop;
  end if;

  update public.stocktakes
  set officer_name = p_payload ->> 'officerName',
      reference_at = ref_ts
  where id = p_id;

  delete from public.stocktake_items where stocktake_id = p_id;

  for line in select * from jsonb_array_elements(p_payload -> 'items') loop
    insert into public.stock_balances (variant_id, condition, quantity)
    values ((line ->> 'variantId')::uuid, (line ->> 'condition')::public.stock_condition, 0)
    on conflict (variant_id, condition) do nothing;

    select coalesce(quantity, 0) into sys_qty from public.stock_balances
    where variant_id = (line ->> 'variantId')::uuid and condition = (line ->> 'condition')::public.stock_condition for update;

    adjustment := (line ->> 'physicalQuantity')::numeric - sys_qty;

    insert into public.stocktake_items (
      stocktake_id, variant_id, condition, system_quantity, physical_quantity, reason, adjustment_quantity
    ) values (
      p_id, (line ->> 'variantId')::uuid, (line ->> 'condition')::public.stock_condition,
      sys_qty, (line ->> 'physicalQuantity')::numeric, nullif(line ->> 'reason', ''), adjustment
    );

    if was_completed and adjustment <> 0 then
      perform public.apply_stock_movement(
        (line ->> 'variantId')::uuid, (line ->> 'condition')::public.stock_condition, adjustment,
        'stocktake_adjustment', 'stocktake', p_id, p_actor,
        coalesce(nullif(line ->> 'reason', ''), 'Revisi ' || st_row.stocktake_no), now()
      );
    end if;
  end loop;

  if not was_completed and finalize_now then
    perform public.finalize_stocktake(p_id, p_actor);
  end if;
  return p_id;
end;
$$;

-- 4. Delete Stocktake (reversing adjustments if finalized)
create or replace function public.delete_stocktake(p_id uuid, p_actor uuid)
returns void language plpgsql security definer set search_path = public as $$
declare st_row public.stocktakes%rowtype;
declare old_line record;
begin
  select * into st_row from public.stocktakes where id = p_id for update;
  if st_row.id is null then raise exception 'Stok opname tidak ditemukan'; end if;

  if st_row.status = 'completed' then
    for old_line in select * from public.stocktake_items where stocktake_id = p_id loop
      if coalesce(old_line.adjustment_quantity, 0) <> 0 then
        perform public.apply_stock_movement(
          old_line.variant_id, old_line.condition, -old_line.adjustment_quantity,
          'stocktake_adjustment', 'stocktake', p_id, p_actor,
          'Hapus ' || st_row.stocktake_no || ' (pembalikan stok)', now()
        );
      end if;
    end loop;
  end if;

  delete from public.stocktake_items where stocktake_id = p_id;
  delete from public.stocktakes where id = p_id;
end;
$$;

-- 5. Delete Opening Stock (reversing stock balances)
create or replace function public.delete_opening_stock(p_id uuid, p_actor uuid)
returns void language plpgsql security definer set search_path = public as $$
declare op_row public.opening_stocks%rowtype;
declare old_line record;
begin
  select * into op_row from public.opening_stocks where id = p_id for update;
  if op_row.id is null then raise exception 'Data stok awal tidak ditemukan'; end if;

  for old_line in select * from public.opening_stock_items where opening_stock_id = p_id loop
    perform public.apply_stock_movement(
      old_line.variant_id, old_line.condition, -old_line.quantity,
      'opening_stock', 'opening_stock', p_id, p_actor,
      'Hapus stok awal ' || op_row.transaction_no, now()
    );
  end loop;

  delete from public.opening_stock_items where opening_stock_id = p_id;
  delete from public.opening_stocks where id = p_id;
end;
$$;

-- 6. Delete Procurement (safely detach any existing receipts so received stock stays intact)
create or replace function public.delete_procurement(p_id uuid)
returns void language plpgsql security definer set search_path = public as $$
declare proc_row public.procurements%rowtype;
begin
  select * into proc_row from public.procurements where id = p_id for update;
  if proc_row.id is null then raise exception 'Pengadaan barang tidak ditemukan'; end if;

  update public.purchase_items
  set procurement_item_id = null
  where procurement_item_id in (select id from public.procurement_items where procurement_id = p_id);

  update public.purchases
  set procurement_id = null
  where procurement_id = p_id;

  delete from public.procurement_payments where procurement_id = p_id;
  delete from public.procurement_items where procurement_id = p_id;
  delete from public.procurements where id = p_id;
end;
$$;

-- 7. Delete Procurement Payment (recalculate paid_amount & status)
create or replace function public.delete_procurement_payment(p_id uuid)
returns void language plpgsql security definer set search_path = public as $$
declare old_pay public.procurement_payments%rowtype;
declare proc_row public.procurements%rowtype;
declare new_paid numeric;
declare new_reimb numeric;
begin
  select * into old_pay from public.procurement_payments where id = p_id for update;
  if old_pay.id is null then raise exception 'Data pembayaran tidak ditemukan'; end if;

  select * into proc_row from public.procurements where id = old_pay.procurement_id for update;
  delete from public.procurement_payments where id = p_id;

  select coalesce(sum(amount), 0) into new_paid from public.procurement_payments where procurement_id = proc_row.id and payment_type <> 'reimbursement';
  select coalesce(sum(amount), 0) into new_reimb from public.procurement_payments where procurement_id = proc_row.id and payment_type = 'reimbursement';

  update public.procurements
  set paid_amount = new_paid,
      payment_status = case when new_paid >= total_amount and total_amount > 0 then 'paid' when new_paid > 0 then 'partial' else 'unpaid' end,
      reimbursement_status = case when funding_source = 'advanced' then (case when new_reimb >= total_amount then 'paid'::public.reimbursement_status when new_reimb > 0 then 'partially_paid'::public.reimbursement_status else 'not_submitted'::public.reimbursement_status end) else null end
  where id = proc_row.id;
end;
$$;

-- 8. Delete Purchase Receipt (reverse stock & update linked procurement received_quantity/status)
create or replace function public.delete_purchase_receipt(p_id uuid, p_actor uuid)
returns void language plpgsql security definer set search_path = public as $$
declare pur_row public.purchases%rowtype;
declare old_line record;
declare total_ord numeric;
declare total_rec numeric;
begin
  select * into pur_row from public.purchases where id = p_id for update;
  if pur_row.id is null then raise exception 'Transaksi barang masuk tidak ditemukan'; end if;

  for old_line in select * from public.purchase_items where purchase_id = p_id loop
    perform public.apply_stock_movement(
      old_line.variant_id, old_line.condition, -old_line.quantity,
      'receipt', 'purchase', p_id, p_actor,
      'Hapus barang masuk ' || pur_row.transaction_no, now()
    );
    if old_line.procurement_item_id is not null then
      update public.procurement_items
      set received_quantity = greatest(0, received_quantity - old_line.quantity)
      where id = old_line.procurement_item_id;
    end if;
  end loop;

  delete from public.reimbursements where purchase_id = p_id;
  delete from public.purchase_items where purchase_id = p_id;
  delete from public.purchases where id = p_id;

  if pur_row.procurement_id is not null then
    select coalesce(sum(ordered_quantity), 0), coalesce(sum(received_quantity), 0)
    into total_ord, total_rec from public.procurement_items where procurement_id = pur_row.procurement_id;

    update public.procurements
    set status = case
      when status = 'cancelled' then 'cancelled'
      when total_rec >= total_ord and total_ord > 0 then 'completed'
      when total_rec > 0 then 'partial'
      else 'ordered'
    end
    where id = pur_row.procurement_id;
  end if;
end;
$$;

-- 9. Delete Issuance (reverse stock if no returns exist)
create or replace function public.delete_issuance(p_id uuid, p_actor uuid)
returns void language plpgsql security definer set search_path = public as $$
declare iss_row public.issuances%rowtype;
declare old_line record;
begin
  select * into iss_row from public.issuances where id = p_id for update;
  if iss_row.id is null then raise exception 'Transaksi barang keluar tidak ditemukan'; end if;

  if exists (select 1 from public.issuance_items where issuance_id = p_id and (returned_quantity > 0 or resolved_lost_quantity > 0)) then
    raise exception 'Barang keluar yang sudah memiliki catatan pengembalian tidak dapat dihapus. Hapus data pengembalian terkait terlebih dahulu.';
  end if;

  for old_line in select * from public.issuance_items where issuance_id = p_id loop
    perform public.apply_stock_movement(
      old_line.variant_id, old_line.condition, old_line.quantity,
      'issuance', 'issuance', p_id, p_actor,
      'Hapus barang keluar ' || iss_row.transaction_no, now()
    );
  end loop;

  delete from public.issuance_items where issuance_id = p_id;
  delete from public.issuances where id = p_id;
end;
$$;

-- 10. Delete Return (reverse employee liability & stock)
create or replace function public.delete_return(p_id uuid, p_actor uuid)
returns void language plpgsql security definer set search_path = public as $$
declare ret_row public.returns%rowtype;
declare old_line record;
declare issue_line public.issuance_items%rowtype;
declare target_condition public.stock_condition;
begin
  select * into ret_row from public.returns where id = p_id for update;
  if ret_row.id is null then raise exception 'Transaksi pengembalian tidak ditemukan'; end if;

  for old_line in select * from public.return_items where return_id = p_id loop
    select * into issue_line from public.issuance_items where id = old_line.issuance_item_id for update;
    if issue_line.id is null then continue; end if;

    if old_line.result = 'lost' then
      update public.issuance_items
      set resolved_lost_quantity = greatest(0, resolved_lost_quantity - old_line.quantity)
      where id = issue_line.id;
    else
      update public.issuance_items
      set returned_quantity = greatest(0, returned_quantity - old_line.quantity)
      where id = issue_line.id;

      if old_line.result = 'used_good' then
        target_condition := 'used_good'::public.stock_condition;
      elsif old_line.result = 'maintenance' then
        target_condition := 'quarantine'::public.stock_condition;
      elsif old_line.result = 'damaged' and old_line.reusable then
        target_condition := 'used_good'::public.stock_condition;
      else
        target_condition := null;
      end if;

      if target_condition is not null then
        perform public.apply_stock_movement(
          issue_line.variant_id, target_condition, -old_line.quantity,
          'return', 'return', p_id, p_actor,
          'Hapus pengembalian ' || ret_row.transaction_no, now()
        );
      end if;
    end if;
  end loop;

  delete from public.return_items where return_id = p_id;
  delete from public.returns where id = p_id;
end;
$$;

revoke execute on function public.delete_stocktake(uuid, uuid) from public, authenticated;
revoke execute on function public.delete_opening_stock(uuid, uuid) from public, authenticated;
revoke execute on function public.delete_procurement(uuid) from public, authenticated;
revoke execute on function public.delete_procurement_payment(uuid) from public, authenticated;
revoke execute on function public.delete_purchase_receipt(uuid, uuid) from public, authenticated;
revoke execute on function public.delete_issuance(uuid, uuid) from public, authenticated;
revoke execute on function public.delete_return(uuid, uuid) from public, authenticated;
