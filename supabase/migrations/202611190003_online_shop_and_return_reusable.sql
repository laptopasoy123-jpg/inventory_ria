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
