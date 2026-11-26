import type { SupabaseClient } from '@supabase/supabase-js'
import type {
  CategoryInput,
  ConditionTransferInput,
  DepartmentInput,
  EmployeeInput,
  FunderInput,
  IssuanceInput,
  ItemInput,
  OfficerInput,
  OpeningStockInput,
  ProcurementInput,
  ProcurementPaymentInput,
  PurchaseInput,
  ReimbursementInput,
  ReturnInput,
  StocktakeCreateInput,
  SupplierInput,
} from '@inventaris/contracts'
import type { InventoryRow, InventoryService } from './service-types'

export class SupabaseInventoryService implements InventoryService {
  constructor(private db: SupabaseClient) {}

  private async resolveActorId(): Promise<string | null> {
    const { data } = await this.db.from('profiles').select('id').eq('active', true).order('created_at').limit(1).maybeSingle()
    return data?.id ?? null
  }

  private toErr(error: unknown, fallback = 'Terjadi kesalahan database'): Error {
    if (error instanceof Error) return error
    const e = error as { message?: string; details?: string } | null
    return new Error(e?.message || e?.details || fallback)
  }

  private async getCurrentBalance(variantId: string, condition: string): Promise<number> {
    const { data, error } = await this.db
      .from('stock_balances')
      .select('quantity')
      .eq('variant_id', variantId)
      .eq('condition', condition)
      .maybeSingle()
    if (error) throw this.toErr(error)
    return Number(data?.quantity ?? 0)
  }

  private async applyStockMovementDirect(
    variantId: string,
    condition: string,
    delta: number,
    movementType: string,
    referenceType: string,
    referenceId: string,
    actorId: string | null,
    notes: string | null,
    occurredAt: string = new Date().toISOString(),
  ): Promise<number> {
    if (delta === 0) return this.getCurrentBalance(variantId, condition)
    const currentQty = await this.getCurrentBalance(variantId, condition)
    const nextQty = currentQty + delta
    if (nextQty < 0) {
      throw new Error(`Stok tidak mencukupi. Stok saat ini ${currentQty}, perubahan ${delta}`)
    }

    const { error: upsErr } = await this.db
      .from('stock_balances')
      .upsert(
        { variant_id: variantId, condition, quantity: nextQty, updated_at: new Date().toISOString() },
        { onConflict: 'variant_id,condition' },
      )
    if (upsErr) throw this.toErr(upsErr)

    const { error: movErr } = await this.db.from('stock_movements').insert({
      variant_id: variantId,
      condition,
      quantity_delta: delta,
      balance_after: nextQty,
      movement_type: movementType,
      reference_type: referenceType,
      reference_id: referenceId,
      notes,
      occurred_at: occurredAt,
      created_by: actorId,
    })
    if (movErr) throw this.toErr(movErr)
    return nextQty
  }

  private async nextStocktakeNo(): Promise<string> {
    const now = new Date()
    const ym = `${now.getFullYear()}${String(now.getMonth() + 1).padStart(2, '0')}`
    const prefix = `SO-${ym}-`
    const { data } = await this.db
      .from('stocktakes')
      .select('stocktake_no')
      .ilike('stocktake_no', `${prefix}%`)
      .order('stocktake_no', { ascending: false })
      .limit(20)
    let maxSeq = 0
    for (const row of data ?? []) {
      const m = String(row.stocktake_no || '').match(/(\d+)$/)
      if (m) maxSeq = Math.max(maxSeq, Number(m[1]))
    }
    return `${prefix}${String(maxSeq + 1).padStart(5, '0')}`
  }

  async getDashboard(month: number, year: number, period: 'all' | 'year' | 'month' = 'all'): Promise<Record<string, unknown>> {
    const [rpcRes, procsRes, unpaidRes, movRes] = await Promise.all([
      this.db.rpc('dashboard_summary', { p_month: month, p_year: year }),
      this.db
        .from('procurement_progress_view')
        .select('*')
        .in('status', ['ordered', 'partial'])
        .order('procurement_date', { ascending: false })
        .limit(6),
      this.db
        .from('procurement_progress_view')
        .select('remaining_amount')
        .neq('status', 'cancelled')
        .neq('payment_status', 'paid'),
      period !== 'month'
        ? this.db
            .from('stock_movements')
            .select('quantity_delta, movement_type, occurred_at, item_variants(items(unit))')
            .in('movement_type', ['opening_stock', 'receipt', 'issuance'])
            .limit(5000)
        : Promise.resolve({ data: null, error: null }),
    ])
    if (rpcRes.error) throw rpcRes.error
    const baseData = (rpcRes.data as Record<string, unknown>) || {}
    const pendingPaymentAmount = (unpaidRes.data ?? []).reduce(
      (acc: number, row: Record<string, unknown>) => acc + Number(row.remaining_amount || 0),
      0,
    )

    let periodFlow = baseData.periodFlow as Array<{ unit: string; incoming: number; outgoing: number }> | undefined
    if (period !== 'month' && Array.isArray(movRes.data)) {
      const flowMap = new Map<string, { unit: string; incoming: number; outgoing: number }>()
      const yearPrefix = `${year}-`
      for (const sm of movRes.data as Array<{
        quantity_delta: number
        movement_type: string
        occurred_at: string
        item_variants?: { items?: { unit?: string } | null } | null
      }>) {
        if (period === 'year' && !String(sm.occurred_at || '').startsWith(yearPrefix)) continue
        const unit = sm.item_variants?.items?.unit || 'pcs'
        const cur = flowMap.get(unit) ?? { unit, incoming: 0, outgoing: 0 }
        const delta = Number(sm.quantity_delta || 0)
        if (delta > 0 && (sm.movement_type === 'receipt' || sm.movement_type === 'opening_stock')) {
          cur.incoming += delta
        } else if (delta < 0 && sm.movement_type === 'issuance') {
          cur.outgoing += Math.abs(delta)
        }
        flowMap.set(unit, cur)
      }
      periodFlow = [...flowMap.values()].sort((a, b) => a.unit.localeCompare(b.unit))
    }

    return {
      ...baseData,
      period,
      periodFlow: periodFlow ?? [],
      activeProcurements: procsRes.data ?? [],
      activeProcurementCount: (procsRes.data ?? []).length,
      pendingPaymentAmount,
    }
  }

  async getMasterSummary() {
    const [departments, items, variants, employees, suppliers, funders, officers] = await Promise.all([
      this.db.from('departments').select('*').order('name'),
      this.db.from('items').select('*, item_variants(id, size, active)').order('name'),
      this.db.from('inventory_view').select('*').order('name'),
      this.db.from('employees').select('*, departments(name, code)').order('name'),
      this.db.from('suppliers').select('*').order('name'),
      this.db.from('funders').select('*').order('name'),
      this.db.from('system_officers').select('*').order('name'),
    ])
    for (const res of [departments, items, variants, employees, suppliers, funders]) {
      if (res.error) throw res.error
    }
    return {
      categories: [],
      departments: departments.data ?? [],
      items: items.data ?? [],
      variants: variants.data ?? [],
      employees: employees.data ?? [],
      suppliers: suppliers.data ?? [],
      funders: funders.data ?? [],
      officers: officers.error ? [] : (officers.data ?? []),
    }
  }

  async saveCategory(_id: string | null, input: CategoryInput) {
    return { id: crypto.randomUUID(), code: input.code, name: input.name }
  }

  async deleteCategory(_id: string) {}

  async saveDepartment(id: string | null, input: DepartmentInput) {
    const payload = { code: input.code, name: input.name, active: input.active }
    const query = id
      ? this.db.from('departments').update(payload).eq('id', id).select().single()
      : this.db.from('departments').insert(payload).select().single()
    const { data, error } = await query
    if (error) throw error
    return data
  }

  async deleteDepartment(id: string) {
    await this.db.from('procurements').update({ department_id: null }).eq('department_id', id)
    const { error } = await this.db.from('departments').delete().eq('id', id)
    if (error) throw this.toErr(error)
  }

  async saveSupplier(id: string | null, input: SupplierInput) {
    const payload = {
      code: input.code,
      name: input.name,
      vendor_type: input.vendorType ?? 'supplier',
      contact_name: input.contactName ?? null,
      phone: input.phone ?? null,
      address: input.address ?? null,
      active: input.active,
    }
    const query = id
      ? this.db.from('suppliers').update(payload).eq('id', id).select().single()
      : this.db.from('suppliers').insert(payload).select().single()
    const { data, error } = await query
    if (error) throw error
    return data
  }

  async deleteSupplier(id: string) {
    const { error } = await this.db.from('suppliers').delete().eq('id', id)
    if (error) throw error
  }

  async saveFunder(id: string | null, input: FunderInput) {
    const payload = { name: input.name, phone: input.phone ?? null, notes: input.notes ?? null, active: input.active }
    const query = id
      ? this.db.from('funders').update(payload).eq('id', id).select().single()
      : this.db.from('funders').insert(payload).select().single()
    const { data, error } = await query
    if (error) throw error
    return data
  }

  async deleteFunder(id: string) {
    await this.db.from('procurements').update({ funder_id: null, funding_source: 'company' }).eq('funder_id', id)
    await this.db.from('purchases').update({ funder_id: null, funding_source: 'company' }).eq('funder_id', id)
    const { error } = await this.db.from('funders').delete().eq('id', id)
    if (error) throw this.toErr(error)
  }

  async saveOfficer(id: string | null, input: OfficerInput) {
    const payload = { name: input.name, role_label: input.roleLabel, active: input.active }
    const query = id
      ? this.db.from('system_officers').update(payload).eq('id', id).select().single()
      : this.db.from('system_officers').insert(payload).select().single()
    const { data, error } = await query
    if (error) throw error
    return data
  }

  async deleteOfficer(id: string) {
    const { error } = await this.db.from('system_officers').delete().eq('id', id)
    if (error) throw error
  }

  async saveEmployee(id: string | null, input: EmployeeInput) {
    const payload = {
      nik: input.nik,
      name: input.name,
      position: input.position,
      department_id: input.departmentId,
      contract_status: input.contractStatus,
    }
    const query = id
      ? this.db.from('employees').update(payload).eq('id', id).select('*, departments(name, code)').single()
      : this.db.from('employees').insert(payload).select('*, departments(name, code)').single()
    const { data, error } = await query
    if (error) throw error
    return data
  }

  async deleteEmployee(id: string) {
    const { data: empReturns } = await this.db.from('returns').select('id').eq('employee_id', id)
    const retIds = (empReturns ?? []).map((r: { id: string }) => r.id)
    if (retIds.length) {
      await this.db.from('return_items').delete().in('return_id', retIds)
      await this.db.from('returns').delete().in('id', retIds)
    }
    const { data: empIss } = await this.db.from('issuances').select('id').eq('employee_id', id)
    const issIds = (empIss ?? []).map((i: { id: string }) => i.id)
    if (issIds.length) {
      const { data: issItems } = await this.db.from('issuance_items').select('id').in('issuance_id', issIds)
      const issItemIds = (issItems ?? []).map((x: { id: string }) => x.id)
      if (issItemIds.length) {
        await this.db.from('return_items').delete().in('issuance_item_id', issItemIds)
      }
      await this.db.from('issuance_items').delete().in('issuance_id', issIds)
      await this.db.from('issuances').delete().in('id', issIds)
    }
    const { error } = await this.db.from('employees').delete().eq('id', id)
    if (error) throw this.toErr(error)
  }

  async saveItem(id: string | null, input: ItemInput) {
    const payload = {
      code: input.code,
      name: input.name,
      specification: input.specification ?? null,
      unit: input.unit,
      minimum_stock: input.minimumStock,
      photo_key: input.photoKey ?? null,
      return_required: input.returnRequired,
      active: input.active,
    }
    const { data: item, error } = id
      ? await this.db.from('items').update(payload).eq('id', id).select().single()
      : await this.db.from('items').insert(payload).select().single()
    if (error) throw error

    const sizes = [...new Set(input.sizes.map((s) => s.trim()).filter(Boolean))]
    if (sizes.length) {
      const rows = sizes.map((size) => ({ item_id: item.id, size, active: true }))
      const { error: varErr } = await this.db
        .from('item_variants')
        .upsert(rows, { onConflict: 'item_id,size' })
      if (varErr) throw varErr
    }
    return item
  }

  async deleteItem(id: string) {
    const { data: variants } = await this.db.from('item_variants').select('id').eq('item_id', id)
    const varIds = (variants ?? []).map((v: { id: string }) => v.id)
    if (varIds.length) {
      const { data: issItems } = await this.db.from('issuance_items').select('id').in('variant_id', varIds)
      const issItemIds = (issItems ?? []).map((x: { id: string }) => x.id)
      if (issItemIds.length) {
        await this.db.from('return_items').delete().in('issuance_item_id', issItemIds)
      }
      await this.db.from('issuance_items').delete().in('variant_id', varIds)
      await this.db.from('purchase_items').delete().in('variant_id', varIds)
      await this.db.from('procurement_items').delete().in('variant_id', varIds)
      await this.db.from('opening_stock_items').delete().in('variant_id', varIds)
      await this.db.from('stocktake_items').delete().in('variant_id', varIds)
      await this.db.from('stock_movements').delete().in('variant_id', varIds)
      await this.db.from('stock_balances').delete().in('variant_id', varIds)
      await this.db.from('item_variants').delete().in('id', varIds)
    }
    const { error } = await this.db.from('items').delete().eq('id', id)
    if (error) throw this.toErr(error)
  }

  async listInventory({ page, limit, search, status }: { page: number; limit: number; search?: string; status?: string; categoryId?: string }) {
    let query = this.db.from('inventory_view').select('*', { count: 'exact' })
    if (search) query = query.or(`code.ilike.%${search}%,name.ilike.%${search}%,size.ilike.%${search}%`)
    if (status && status !== 'all') query = query.eq('stock_status', status)
    const { data, count, error } = await query
      .order('name')
      .range((page - 1) * limit, page * limit - 1)
    if (error) throw error
    return {
      data: (data ?? []) as InventoryRow[],
      pagination: { page, limit, total: count ?? 0, totalPages: Math.ceil((count ?? 0) / limit) },
    }
  }

  async listMovements({ variantId, limit = 100 }: { variantId?: string; limit?: number }) {
    let query = this.db
      .from('stock_movements')
      .select('*, item_variants(size, items(code, name, unit)), profiles(full_name)')
      .order('occurred_at', { ascending: false })
      .order('id', { ascending: false })
      .limit(limit)
    if (variantId) query = query.eq('variant_id', variantId)
    const { data, error } = await query
    if (error) throw error
    return data ?? []
  }

  async listOpeningStocks() {
    const { data, error } = await this.db
      .from('opening_stocks')
      .select('*, opening_stock_items(*, item_variants(size, items(code, name, unit)))')
      .order('recorded_at', { ascending: false })
      .limit(50)
    if (error) throw error
    return data ?? []
  }

  async createOpeningStock(input: OpeningStockInput, idempotencyKey: string): Promise<string> {
    const { data, error } = await this.db.rpc('create_opening_stock', {
      p_payload: { ...input, idempotencyKey },
      p_actor: await this.resolveActorId(),
    })
    if (error) throw error
    return data as string
  }

  async updateOpeningStock(id: string, input: OpeningStockInput): Promise<string> {
    const { data, error } = await this.db.rpc('update_opening_stock', {
      p_id: id,
      p_payload: input,
      p_actor: await this.resolveActorId(),
    })
    if (error) throw error
    return data as string
  }

  async deleteOpeningStock(id: string): Promise<void> {
    const actorId = await this.resolveActorId()
    const { data: opRow, error: fetchErr } = await this.db
      .from('opening_stocks')
      .select('id, transaction_no, opening_stock_items(variant_id, condition, quantity)')
      .eq('id', id)
      .maybeSingle()
    if (fetchErr) throw this.toErr(fetchErr)
    if (!opRow) throw new Error('Data stok awal tidak ditemukan')

    const items = (opRow.opening_stock_items ?? []) as Array<{ variant_id: string; condition: string; quantity: number }>
    for (const line of items) {
      const cur = await this.getCurrentBalance(line.variant_id, line.condition)
      const delta = -Math.min(cur, Number(line.quantity))
      if (delta !== 0) {
        await this.applyStockMovementDirect(
          line.variant_id,
          line.condition,
          delta,
          'opening_stock',
          'opening_stock',
          id,
          actorId,
          `Hapus stok awal ${opRow.transaction_no}`,
        )
      }
    }
    const { error: delItemsErr } = await this.db.from('opening_stock_items').delete().eq('opening_stock_id', id)
    if (delItemsErr) throw this.toErr(delItemsErr)
    const { error: delErr } = await this.db.from('opening_stocks').delete().eq('id', id)
    if (delErr) throw this.toErr(delErr)
  }

  async transferCondition(input: ConditionTransferInput): Promise<string> {
    const { data, error } = await this.db.rpc('transfer_stock_condition', {
      p_payload: input,
      p_actor: await this.resolveActorId(),
    })
    if (error) throw error
    return data as string
  }

  async listProcurements({ status, paymentStatus, search, variantId, onlyPendingReceipt }: {
    status?: string
    paymentStatus?: string
    search?: string
    variantId?: string
    onlyPendingReceipt?: boolean
  }) {
    let query = this.db.from('procurement_progress_view').select('*').order('created_at', { ascending: false })
    if (onlyPendingReceipt) query = query.in('status', ['ordered', 'partial'])
    else if (status && status !== 'all') query = query.eq('status', status)
    if (paymentStatus && paymentStatus !== 'all') query = query.eq('payment_status', paymentStatus)
    if (search) {
      query = query.or(`procurement_no.ilike.%${search}%,po_number.ilike.%${search}%,pr_number.ilike.%${search}%,supplier_name.ilike.%${search}%,reason.ilike.%${search}%`)
    }
    const { data: procs, error } = await query.limit(100)
    if (error) throw error
    if (!procs?.length) return []

    const ids = procs.map((p: Record<string, unknown>) => String(p.id))
    const { data: items, error: itemErr } = await this.db
      .from('procurement_items')
      .select('*, item_variants(id, size, items(id, code, name, unit, photo_key))')
      .in('procurement_id', ids)
    if (itemErr) throw itemErr

    const byProc = new Map<string, Record<string, unknown>[]>()
    for (const item of items ?? []) {
      const arr = byProc.get(item.procurement_id) ?? []
      arr.push(item)
      byProc.set(item.procurement_id, arr)
    }

    let result = procs.map((p: Record<string, unknown>) => ({ ...p, items: byProc.get(String(p.id)) ?? [] }))
    if (variantId) {
      result = result.filter((p: Record<string, unknown> & { items: Record<string, unknown>[] }) =>
        p.items.some((item: Record<string, unknown>) =>
          item.variant_id === variantId && Number(item.ordered_quantity) > Number(item.received_quantity),
        ),
      )
    }
    return result
  }

  async getProcurement(id: string) {
    const [procRes, itemsRes, receiptsRes, paymentsRes] = await Promise.all([
      this.db.from('procurement_progress_view').select('*').eq('id', id).single(),
      this.db.from('procurement_items').select('*, item_variants(id, size, items(id, code, name, unit, photo_key))').eq('procurement_id', id),
      this.db.from('purchases').select('*, purchase_items(*, item_variants(size, items(code, name, unit, photo_key)))').eq('procurement_id', id).order('received_date', { ascending: false }),
      this.db.from('procurement_payments').select('*').eq('procurement_id', id).order('paid_at', { ascending: false }),
    ])
    if (procRes.error) throw procRes.error
    return {
      ...procRes.data,
      items: itemsRes.data ?? [],
      receipts: receiptsRes.data ?? [],
      payments: paymentsRes.data ?? [],
    }
  }

  async createProcurement(input: ProcurementInput, idempotencyKey: string): Promise<string> {
    const { data, error } = await this.db.rpc('create_procurement', {
      p_payload: { ...input, idempotencyKey },
      p_actor: await this.resolveActorId(),
    })
    if (error) throw error
    return data as string
  }

  async updateProcurement(id: string, input: ProcurementInput): Promise<string> {
    const { data: proc, error: fetchErr } = await this.db
      .from('procurements')
      .select('id, status, paid_amount, procurement_items(id, variant_id, ordered_quantity, received_quantity)')
      .eq('id', id)
      .maybeSingle()
    if (fetchErr) throw this.toErr(fetchErr)
    if (!proc) throw new Error('Pengadaan tidak ditemukan')

    const calcTotal = input.items.reduce((s, item) => s + Number(item.orderedQuantity) * Number(item.unitPrice || 0), 0)
    const payloadTotal = input.totalAmount !== undefined && Number(input.totalAmount) > 0 ? Number(input.totalAmount) : calcTotal

    const existingItems = (proc.procurement_items ?? []) as Array<{
      id: string; variant_id: string; ordered_quantity: number; received_quantity: number
    }>
    const existingMap = new Map(existingItems.map((it) => [it.id, it]))
    const keptIds: string[] = []

    for (const line of input.items) {
      if (line.id && existingMap.has(line.id)) {
        const old = existingMap.get(line.id)!
        const { error: uErr } = await this.db
          .from('procurement_items')
          .update({
            variant_id: line.variantId,
            ordered_quantity: Number(line.orderedQuantity),
            received_quantity: Math.min(Number(old.received_quantity || 0), Number(line.orderedQuantity)),
            unit_price: Number(line.unitPrice || 0),
            notes: line.notes || null,
          })
          .eq('id', line.id)
        if (uErr) throw this.toErr(uErr)
        keptIds.push(line.id)
      } else {
        const { data: ins, error: iErr } = await this.db
          .from('procurement_items')
          .insert({
            procurement_id: id,
            variant_id: line.variantId,
            ordered_quantity: Number(line.orderedQuantity),
            unit_price: Number(line.unitPrice || 0),
            notes: line.notes || null,
          })
          .select('id')
          .single()
        if (iErr) throw this.toErr(iErr)
        keptIds.push(String(ins.id))
      }
    }

    const removedIds = existingItems.map((it) => it.id).filter((oid) => !keptIds.includes(oid))
    if (removedIds.length) {
      await this.db.from('purchase_items').update({ procurement_item_id: null }).in('procurement_item_id', removedIds)
      await this.db.from('procurement_items').delete().in('id', removedIds)
    }

    const { data: finalItems } = await this.db
      .from('procurement_items')
      .select('ordered_quantity, received_quantity')
      .eq('procurement_id', id)
    const list = (finalItems ?? []) as Array<{ ordered_quantity: number; received_quantity: number }>
    const totalOrd = list.reduce((s, x) => s + Number(x.ordered_quantity || 0), 0)
    const totalRec = list.reduce((s, x) => s + Number(x.received_quantity || 0), 0)
    const paidAmount = Number(proc.paid_amount || 0)
    const nextPayStatus = paidAmount >= payloadTotal && payloadTotal > 0 ? 'paid' : paidAmount > 0 ? 'partial' : 'unpaid'
    const nextStatus = proc.status === 'cancelled'
      ? 'cancelled'
      : totalRec >= totalOrd && totalOrd > 0
        ? 'completed'
        : totalRec > 0
          ? 'partial'
          : 'ordered'

    const { error: updErr } = await this.db
      .from('procurements')
      .update({
        procurement_date: new Date(input.procurementDate).toISOString().slice(0, 10),
        expected_date: input.expectedDate ? new Date(input.expectedDate).toISOString().slice(0, 10) : null,
        pr_number: input.prNumber || null,
        po_number: input.poNumber || null,
        department_id: input.departmentId || null,
        supplier_id: input.supplierId,
        reason: input.reason,
        funding_source: input.fundingSource,
        payment_method: input.paymentMethod,
        funder_id: input.fundingSource === 'advanced' ? (input.funderId || null) : null,
        total_amount: payloadTotal,
        payment_status: nextPayStatus,
        status: nextStatus,
        notes: input.notes || null,
      })
      .eq('id', id)
    if (updErr) throw this.toErr(updErr)
    return id
  }

  async deleteProcurement(id: string): Promise<void> {
    const { data: procItems } = await this.db.from('procurement_items').select('id').eq('procurement_id', id)
    const itemIds = (procItems ?? []).map((x: { id: string }) => x.id)
    if (itemIds.length) {
      await this.db.from('purchase_items').update({ procurement_item_id: null }).in('procurement_item_id', itemIds)
    }
    await this.db.from('purchases').update({ procurement_id: null }).eq('procurement_id', id)
    await this.db.from('procurement_payments').delete().eq('procurement_id', id)
    await this.db.from('procurement_items').delete().eq('procurement_id', id)
    const { error } = await this.db.from('procurements').delete().eq('id', id)
    if (error) throw this.toErr(error)
  }

  async updateProcurementStatus(id: string, status: string, cancelNote?: string) {
    const { data: proc, error: fetchErr } = await this.db
      .from('procurements')
      .select('status, notes, procurement_items(ordered_quantity, received_quantity)')
      .eq('id', id)
      .maybeSingle()
    if (fetchErr) throw this.toErr(fetchErr)
    if (!proc) throw new Error('Pengadaan tidak ditemukan')

    if (status === 'cancelled' && proc.status === 'completed') {
      throw new Error('Pengadaan yang sudah terpenuhi 100% tidak dapat dibatalkan')
    }

    let nextStatus = status
    if (status !== 'cancelled') {
      const items = (proc.procurement_items as Array<{ ordered_quantity: number; received_quantity: number }> | null) ?? []
      const totalOrdered = items.reduce((s, i) => s + Number(i.ordered_quantity || 0), 0)
      const totalReceived = items.reduce((s, i) => s + Number(i.received_quantity || 0), 0)
      if (totalOrdered > 0 && totalReceived >= totalOrdered) {
        nextStatus = 'completed'
      } else if (totalReceived > 0) {
        nextStatus = 'partial'
      } else {
        nextStatus = 'ordered'
      }
    }

    const updatePayload: Record<string, unknown> = { status: nextStatus }
    const cleanedPrevNotes = String(proc.notes || '')
      .replace(/(?:\s*·\s*)?\[(?:Alasan Cancel|Batal Cancel):[^\]]*\]/g, '')
      .replace(/^\s*·\s*/, '')
      .trim()

    if (status === 'cancelled') {
      if (cancelNote?.trim()) {
        const tag = `[Alasan Cancel: ${cancelNote.trim()}]`
        updatePayload.notes = cleanedPrevNotes ? `${cleanedPrevNotes} · ${tag}` : tag
      }
    } else {
      if (cancelNote?.trim()) {
        const tag = `[Batal Cancel: ${cancelNote.trim()}]`
        updatePayload.notes = cleanedPrevNotes ? `${cleanedPrevNotes} · ${tag}` : tag
      } else {
        updatePayload.notes = cleanedPrevNotes || null
      }
    }

    const { error } = await this.db.from('procurements').update(updatePayload).eq('id', id)
    if (error) throw this.toErr(error)
  }

  async createProcurementPayment(input: ProcurementPaymentInput): Promise<string> {
    const { data, error } = await this.db.rpc('create_procurement_payment', {
      p_payload: input,
      p_actor: await this.resolveActorId(),
    })
    if (error) throw error
    return data as string
  }

  async updateProcurementPayment(id: string, input: ProcurementPaymentInput): Promise<string> {
    const { data, error } = await this.db.rpc('update_procurement_payment', {
      p_id: id,
      p_payload: input,
      p_actor: await this.resolveActorId(),
    })
    if (error) throw error
    return data as string
  }

  async deleteProcurementPayment(id: string): Promise<void> {
    const { data: pay, error: fetchErr } = await this.db
      .from('procurement_payments')
      .select('id, procurement_id')
      .eq('id', id)
      .maybeSingle()
    if (fetchErr) throw this.toErr(fetchErr)
    if (!pay) throw new Error('Data pembayaran tidak ditemukan')

    const { error: delErr } = await this.db.from('procurement_payments').delete().eq('id', id)
    if (delErr) throw this.toErr(delErr)

    const [{ data: proc }, { data: remainingPays }] = await Promise.all([
      this.db.from('procurements').select('id, total_amount, funding_source').eq('id', pay.procurement_id).maybeSingle(),
      this.db.from('procurement_payments').select('amount, payment_type').eq('procurement_id', pay.procurement_id),
    ])
    if (proc) {
      const list = (remainingPays ?? []) as Array<{ amount: number; payment_type: string }>
      const newPaid = list.filter((x) => x.payment_type !== 'reimbursement').reduce((s, x) => s + Number(x.amount), 0)
      const newReimb = list.filter((x) => x.payment_type === 'reimbursement').reduce((s, x) => s + Number(x.amount), 0)
      const total = Number(proc.total_amount || 0)
      const paymentStatus = newPaid >= total && total > 0 ? 'paid' : newPaid > 0 ? 'partial' : 'unpaid'
      const reimbStatus = proc.funding_source === 'advanced'
        ? (newReimb >= total ? 'paid' : newReimb > 0 ? 'partially_paid' : 'not_submitted')
        : null
      await this.db
        .from('procurements')
        .update({ paid_amount: newPaid, payment_status: paymentStatus, reimbursement_status: reimbStatus })
        .eq('id', proc.id)
    }
  }

  async listPayments() {
    const { data, error } = await this.db
      .from('procurement_payments')
      .select('*, procurements(procurement_no, po_number, total_amount, funding_source, suppliers(name))')
      .order('paid_at', { ascending: false })
      .limit(100)
    if (error) throw error
    return data ?? []
  }

  async listPurchases({ fundingSource, search }: { fundingSource?: string; search?: string }) {
    let query = this.db
      .from('purchases')
      .select('*, suppliers(name, code, vendor_type), procurements(procurement_no, po_number), purchase_items(*, item_variants(size, items(code, name, unit, photo_key)))')
      .order('received_date', { ascending: false })
      .limit(100)
    if (fundingSource && fundingSource !== 'all') query = query.eq('funding_source', fundingSource)
    if (search) query = query.or(`transaction_no.ilike.%${search}%,po_number.ilike.%${search}%,delivery_note_number.ilike.%${search}%,reason.ilike.%${search}%`)
    const { data, error } = await query
    if (error) throw error
    return data ?? []
  }

  async createPurchaseReceipt(input: PurchaseInput, idempotencyKey: string): Promise<string> {
    const { data, error } = await this.db.rpc('create_purchase_receipt', {
      p_payload: { ...input, idempotencyKey },
      p_actor: await this.resolveActorId(),
    })
    if (error) throw error
    return data as string
  }

  async updatePurchaseReceipt(id: string, input: PurchaseInput): Promise<string> {
    const { data, error } = await this.db.rpc('update_purchase_receipt', {
      p_id: id,
      p_payload: input,
      p_actor: await this.resolveActorId(),
    })
    if (error) throw error
    return data as string
  }

  async deletePurchaseReceipt(id: string): Promise<void> {
    const actorId = await this.resolveActorId()
    const { data: purRow, error: fetchErr } = await this.db
      .from('purchases')
      .select('id, transaction_no, procurement_id, purchase_items(id, variant_id, condition, quantity, procurement_item_id)')
      .eq('id', id)
      .maybeSingle()
    if (fetchErr) throw this.toErr(fetchErr)
    if (!purRow) throw new Error('Transaksi barang masuk tidak ditemukan')

    const items = (purRow.purchase_items ?? []) as Array<{
      id: string; variant_id: string; condition: string; quantity: number; procurement_item_id: string | null
    }>
    for (const line of items) {
      const cur = await this.getCurrentBalance(line.variant_id, line.condition)
      const delta = -Math.min(cur, Number(line.quantity))
      if (delta !== 0) {
        await this.applyStockMovementDirect(
          line.variant_id,
          line.condition,
          delta,
          'receipt',
          'purchase',
          id,
          actorId,
          `Hapus barang masuk ${purRow.transaction_no}`,
        )
      }
      if (line.procurement_item_id) {
        const { data: pi } = await this.db
          .from('procurement_items')
          .select('received_quantity')
          .eq('id', line.procurement_item_id)
          .maybeSingle()
        if (pi) {
          await this.db
            .from('procurement_items')
            .update({ received_quantity: Math.max(0, Number(pi.received_quantity || 0) - Number(line.quantity)) })
            .eq('id', line.procurement_item_id)
        }
      }
    }

    await this.db.from('reimbursements').delete().eq('purchase_id', id)
    const { error: delItemsErr } = await this.db.from('purchase_items').delete().eq('purchase_id', id)
    if (delItemsErr) throw this.toErr(delItemsErr)
    const { error: delErr } = await this.db.from('purchases').delete().eq('id', id)
    if (delErr) throw this.toErr(delErr)

    if (purRow.procurement_id) {
      const [{ data: proc }, { data: procItems }] = await Promise.all([
        this.db.from('procurements').select('id, status').eq('id', purRow.procurement_id).maybeSingle(),
        this.db.from('procurement_items').select('ordered_quantity, received_quantity').eq('procurement_id', purRow.procurement_id),
      ])
      if (proc && proc.status !== 'cancelled') {
        const list = (procItems ?? []) as Array<{ ordered_quantity: number; received_quantity: number }>
        const totalOrd = list.reduce((s, x) => s + Number(x.ordered_quantity || 0), 0)
        const totalRec = list.reduce((s, x) => s + Number(x.received_quantity || 0), 0)
        const nextStatus = totalRec >= totalOrd && totalOrd > 0 ? 'completed' : totalRec > 0 ? 'partial' : 'ordered'
        await this.db.from('procurements').update({ status: nextStatus }).eq('id', proc.id)
      }
    }
  }

  async listIssuances({ search, employeeId }: { search?: string; employeeId?: string }) {
    let query = this.db
      .from('issuances')
      .select('*, employees(nik, name, position, departments(name)), issuance_items(*, item_variants(size, items(code, name, unit, return_required, photo_key)))')
      .order('issued_at', { ascending: false })
      .limit(100)
    if (employeeId) query = query.eq('employee_id', employeeId)
    if (search) query = query.or(`transaction_no.ilike.%${search}%,officer_name.ilike.%${search}%,notes.ilike.%${search}%`)
    const { data, error } = await query
    if (error) throw error
    return data ?? []
  }

  async listOpenIssuanceItemsByEmployee(employeeId: string) {
    const { data, error } = await this.db
      .from('issuance_items')
      .select('*, issuances!inner(id, transaction_no, issued_at, employee_id), item_variants(id, size, items(code, name, unit, return_required))')
      .eq('issuances.employee_id', employeeId)
    if (error) throw error
    return (data ?? []).filter((row: Record<string, unknown>) => Number(row.quantity) - Number(row.returned_quantity) - Number(row.resolved_lost_quantity) > 0)
  }

  async createIssuance(input: IssuanceInput, idempotencyKey: string): Promise<string> {
    const { data, error } = await this.db.rpc('create_issuance', {
      p_payload: { ...input, idempotencyKey },
      p_actor: await this.resolveActorId(),
    })
    if (error) throw error
    return data as string
  }

  private async detachAndReverseReturnsForIssuanceItems(
    issItemIds: string[],
    issItemMap: Map<string, { variant_id: string }>,
    actorId: string | null,
    reasonPrefix: string,
  ): Promise<void> {
    if (!issItemIds.length) return
    const { data: linkedRetItems } = await this.db
      .from('return_items')
      .select('id, return_id, issuance_item_id, quantity, result, reusable')
      .in('issuance_item_id', issItemIds)

    const retItems = (linkedRetItems ?? []) as Array<{
      id: string; return_id: string; issuance_item_id: string; quantity: number; result: string; reusable?: boolean
    }>
    if (!retItems.length) return

    const touchedReturnIds = new Set<string>()
    for (const ri of retItems) {
      touchedReturnIds.add(ri.return_id)
      const parentItem = issItemMap.get(ri.issuance_item_id)
      if (!parentItem || ri.result === 'lost') continue
      const targetCond =
        ri.result === 'used_good' ? 'used_good'
          : ri.result === 'maintenance' ? 'quarantine'
            : ri.result === 'damaged' && ri.reusable ? 'used_good'
              : null
      if (targetCond) {
        const cur = await this.getCurrentBalance(parentItem.variant_id, targetCond)
        const delta = -Math.min(cur, Number(ri.quantity))
        if (delta !== 0) {
          await this.applyStockMovementDirect(
            parentItem.variant_id,
            targetCond,
            delta,
            'return',
            'return',
            ri.return_id,
            actorId,
            reasonPrefix,
          )
        }
      }
    }

    await this.db.from('return_items').delete().in('id', retItems.map((x) => x.id))
    for (const retId of touchedReturnIds) {
      const { count } = await this.db.from('return_items').select('id', { count: 'exact', head: true }).eq('return_id', retId)
      if ((count ?? 0) === 0) {
        await this.db.from('returns').delete().eq('id', retId)
      }
    }
  }

  async updateIssuance(id: string, input: IssuanceInput): Promise<string> {
    const actorId = await this.resolveActorId()
    const { data: issRow, error: fetchErr } = await this.db
      .from('issuances')
      .select('id, transaction_no, handover_proof_key, issuance_items(id, variant_id, condition, quantity, returned_quantity, resolved_lost_quantity)')
      .eq('id', id)
      .maybeSingle()
    if (fetchErr) throw this.toErr(fetchErr)
    if (!issRow) throw new Error('Transaksi barang keluar tidak ditemukan')

    const oldItems = (issRow.issuance_items ?? []) as Array<{
      id: string; variant_id: string; condition: string; quantity: number; returned_quantity: number; resolved_lost_quantity: number
    }>
    const hasReturns = oldItems.some((it) => Number(it.returned_quantity || 0) > 0 || Number(it.resolved_lost_quantity || 0) > 0)

    if (hasReturns) {
      const issItemMap = new Map(oldItems.map((it) => [it.id, { variant_id: it.variant_id }]))
      await this.detachAndReverseReturnsForIssuanceItems(
        oldItems.map((it) => it.id),
        issItemMap,
        actorId,
        `Revisi barang keluar ${issRow.transaction_no} (penyesuaian pengembalian)`,
      )
    }

    for (const old of oldItems) {
      await this.applyStockMovementDirect(
        old.variant_id,
        old.condition,
        Number(old.quantity),
        'issuance',
        'issuance',
        id,
        actorId,
        `Revisi barang keluar ${issRow.transaction_no} (koreksi)`,
      )
    }

    const { error: delItemsErr } = await this.db.from('issuance_items').delete().eq('issuance_id', id)
    if (delItemsErr) throw this.toErr(delItemsErr)

    const issuedDate = new Date(input.issuedAt).toISOString().slice(0, 10)
    const { error: updErr } = await this.db
      .from('issuances')
      .update({
        issued_at: issuedDate,
        employee_id: input.employeeId,
        officer_name: input.officerName,
        handover_proof_key: input.handoverProofKey || issRow.handover_proof_key || null,
        notes: input.notes || null,
      })
      .eq('id', id)
    if (updErr) throw this.toErr(updErr)

    const occurredAt = this.normalizeReferenceAt(input.issuedAt)
    for (const line of input.items) {
      const reqQty = Number(line.quantity)
      if (!line.condition || line.condition === 'auto') {
        const curNew = await this.getCurrentBalance(line.variantId, 'new')
        const curUsed = await this.getCurrentBalance(line.variantId, 'used_good')
        if (curNew + curUsed < reqQty) {
          throw new Error(`Stok tersedia tidak mencukupi (tersedia ${curNew + curUsed})`)
        }
        const takeNew = Math.min(curNew, reqQty)
        const takeUsed = reqQty - takeNew
        if (takeNew > 0) {
          const { error: iErr } = await this.db.from('issuance_items').insert({
            issuance_id: id, variant_id: line.variantId, condition: 'new', quantity: takeNew, purpose: line.purpose, notes: line.notes || null,
          })
          if (iErr) throw this.toErr(iErr)
          await this.applyStockMovementDirect(line.variantId, 'new', -takeNew, 'issuance', 'issuance', id, actorId, line.purpose, occurredAt)
        }
        if (takeUsed > 0) {
          const { error: iErr } = await this.db.from('issuance_items').insert({
            issuance_id: id, variant_id: line.variantId, condition: 'used_good', quantity: takeUsed, purpose: line.purpose, notes: line.notes || null,
          })
          if (iErr) throw this.toErr(iErr)
          await this.applyStockMovementDirect(line.variantId, 'used_good', -takeUsed, 'issuance', 'issuance', id, actorId, line.purpose, occurredAt)
        }
      } else {
        const { error: iErr } = await this.db.from('issuance_items').insert({
          issuance_id: id, variant_id: line.variantId, condition: line.condition, quantity: reqQty, purpose: line.purpose, notes: line.notes || null,
        })
        if (iErr) throw this.toErr(iErr)
        await this.applyStockMovementDirect(line.variantId, line.condition, -reqQty, 'issuance', 'issuance', id, actorId, line.purpose, occurredAt)
      }
    }

    return id
  }

  async deleteIssuance(id: string): Promise<void> {
    const actorId = await this.resolveActorId()
    const { data: issRow, error: fetchErr } = await this.db
      .from('issuances')
      .select('id, transaction_no, issuance_items(id, variant_id, condition, quantity, returned_quantity, resolved_lost_quantity)')
      .eq('id', id)
      .maybeSingle()
    if (fetchErr) throw this.toErr(fetchErr)
    if (!issRow) throw new Error('Transaksi barang keluar tidak ditemukan')

    const items = (issRow.issuance_items ?? []) as Array<{
      id: string; variant_id: string; condition: string; quantity: number; returned_quantity: number; resolved_lost_quantity: number
    }>
    const issItemMap = new Map(items.map((it) => [it.id, { variant_id: it.variant_id }]))
    await this.detachAndReverseReturnsForIssuanceItems(
      items.map((it) => it.id),
      issItemMap,
      actorId,
      `Hapus barang keluar ${issRow.transaction_no} (pembalikan pengembalian)`,
    )

    for (const line of items) {
      await this.applyStockMovementDirect(
        line.variant_id,
        line.condition,
        Number(line.quantity),
        'issuance',
        'issuance',
        id,
        actorId,
        `Hapus barang keluar ${issRow.transaction_no}`,
      )
    }

    const { error: delItemsErr } = await this.db.from('issuance_items').delete().eq('issuance_id', id)
    if (delItemsErr) throw this.toErr(delItemsErr)
    const { error: delErr } = await this.db.from('issuances').delete().eq('id', id)
    if (delErr) throw this.toErr(delErr)
  }

  async listReturns({ result, search }: { result?: string; search?: string }) {
    let query = this.db
      .from('returns')
      .select('*, employees(nik, name, departments(name)), return_items(*, issuance_items(condition, item_variants(size, items(code, name, unit))))')
      .order('returned_at', { ascending: false })
      .limit(100)
    if (search) query = query.or(`transaction_no.ilike.%${search}%,inspector_name.ilike.%${search}%`)
    const { data, error } = await query
    if (error) throw error
    if (!result || result === 'all') return data ?? []
    return (data ?? []).filter((ret: { return_items?: Array<{ result: string }> }) =>
      (ret.return_items ?? []).some((item: { result: string }) => item.result === result),
    )
  }

  async createReturn(input: ReturnInput, idempotencyKey: string): Promise<string> {
    const { data, error } = await this.db.rpc('create_return', {
      p_payload: { ...input, idempotencyKey },
      p_actor: await this.resolveActorId(),
    })
    if (error) throw error
    return data as string
  }

  async updateReturn(id: string, input: ReturnInput): Promise<string> {
    const { data, error } = await this.db.rpc('update_return', {
      p_id: id,
      p_payload: input,
      p_actor: await this.resolveActorId(),
    })
    if (error) throw error
    return data as string
  }

  async deleteReturn(id: string): Promise<void> {
    const actorId = await this.resolveActorId()
    const { data: retRow, error: fetchErr } = await this.db
      .from('returns')
      .select('id, transaction_no, return_items(id, issuance_item_id, quantity, result, reusable)')
      .eq('id', id)
      .maybeSingle()
    if (fetchErr) throw this.toErr(fetchErr)
    if (!retRow) throw new Error('Transaksi pengembalian tidak ditemukan')

    const items = (retRow.return_items ?? []) as Array<{
      id: string; issuance_item_id: string; quantity: number; result: string; reusable?: boolean
    }>
    for (const old of items) {
      const { data: issueLine } = await this.db
        .from('issuance_items')
        .select('id, variant_id, returned_quantity, resolved_lost_quantity')
        .eq('id', old.issuance_item_id)
        .maybeSingle()
      if (!issueLine) continue

      const qty = Number(old.quantity)
      if (old.result === 'lost') {
        await this.db
          .from('issuance_items')
          .update({ resolved_lost_quantity: Math.max(0, Number(issueLine.resolved_lost_quantity || 0) - qty) })
          .eq('id', issueLine.id)
      } else {
        await this.db
          .from('issuance_items')
          .update({ returned_quantity: Math.max(0, Number(issueLine.returned_quantity || 0) - qty) })
          .eq('id', issueLine.id)

        const targetCond =
          old.result === 'used_good' ? 'used_good'
            : old.result === 'maintenance' ? 'quarantine'
              : old.result === 'damaged' && old.reusable ? 'used_good'
                : null
        if (targetCond) {
          const cur = await this.getCurrentBalance(issueLine.variant_id, targetCond)
          const delta = -Math.min(cur, qty)
          if (delta !== 0) {
            await this.applyStockMovementDirect(
              issueLine.variant_id,
              targetCond,
              delta,
              'return',
              'return',
              id,
              actorId,
              `Hapus pengembalian ${retRow.transaction_no}`,
            )
          }
        }
      }
    }

    const { error: delItemsErr } = await this.db.from('return_items').delete().eq('return_id', id)
    if (delItemsErr) throw this.toErr(delItemsErr)
    const { error: delErr } = await this.db.from('returns').delete().eq('id', id)
    if (delErr) throw this.toErr(delErr)
  }

  async listStocktakes({ status }: { status?: string }) {
    let query = this.db
      .from('stocktakes')
      .select('*, stocktake_items(*, item_variants(size, items(code, name, unit)))')
      .order('created_at', { ascending: false })
      .limit(100)
    if (status && status !== 'all') query = query.eq('status', status)
    const { data, error } = await query
    if (error) throw this.toErr(error)
    return data ?? []
  }

  private normalizeReferenceAt(refInput?: Date | string): string {
    const now = new Date()
    if (!refInput) return now.toISOString()
    const d = new Date(refInput)
    if (Number.isNaN(d.getTime())) return now.toISOString()
    const refDatePart = d.toISOString().slice(0, 10)
    const todayUtc = now.toISOString().slice(0, 10)
    const todayWib = new Date(now.getTime() + 7 * 3600 * 1000).toISOString().slice(0, 10)
    return refDatePart === todayUtc || refDatePart === todayWib ? now.toISOString() : d.toISOString()
  }

  async createStocktake(input: StocktakeCreateInput): Promise<string> {
    const actorId = await this.resolveActorId()
    const nowIso = new Date().toISOString()
    const stocktakeNo = await this.nextStocktakeNo()
    const refTs = this.normalizeReferenceAt(input.referenceAt)

    const { data: stRow, error: insErr } = await this.db
      .from('stocktakes')
      .insert({
        stocktake_no: stocktakeNo,
        reference_at: refTs,
        officer_name: input.officerName,
        status: input.finalizeNow ? 'completed' : 'pending_review',
        submitted_at: nowIso,
        finalized_at: input.finalizeNow ? nowIso : null,
        finalized_by: input.finalizeNow ? actorId : null,
        created_by: actorId,
      })
      .select('id')
      .single()
    if (insErr) throw this.toErr(insErr)
    const stId = String(stRow.id)

    const { data: allBalances, error: balErr } = await this.db
      .from('stock_balances')
      .select('variant_id, condition, quantity')
    if (balErr) throw this.toErr(balErr)
    const balMap = new Map<string, number>()
    for (const b of allBalances ?? []) {
      balMap.set(`${b.variant_id}:${b.condition}`, Number(b.quantity ?? 0))
    }

    const itemRows = input.items.map((line) => {
      const sysQty = balMap.get(`${line.variantId}:${line.condition}`) ?? 0
      const physQty = Number(line.physicalQuantity)
      return {
        stocktake_id: stId,
        variant_id: line.variantId,
        condition: line.condition,
        system_quantity: sysQty,
        physical_quantity: physQty,
        reason: line.reason || null,
        adjustment_quantity: physQty - sysQty,
      }
    })

    const { error: itemsErr } = await this.db.from('stocktake_items').insert(itemRows)
    if (itemsErr) throw this.toErr(itemsErr)

    if (input.finalizeNow) {
      for (const row of itemRows) {
        if (row.adjustment_quantity !== 0) {
          await this.applyStockMovementDirect(
            row.variant_id,
            row.condition,
            row.adjustment_quantity,
            'stocktake_adjustment',
            'stocktake',
            stId,
            actorId,
            row.reason || `Penyesuaian ${stocktakeNo}`,
            nowIso,
          )
        }
      }
    }

    return stId
  }

  async updateStocktake(id: string, input: StocktakeCreateInput): Promise<string> {
    const actorId = await this.resolveActorId()
    const nowIso = new Date().toISOString()
    const { data: stRow, error: fetchErr } = await this.db
      .from('stocktakes')
      .select('id, stocktake_no, status, reference_at, stocktake_items(variant_id, condition, system_quantity, physical_quantity, adjustment_quantity)')
      .eq('id', id)
      .maybeSingle()
    if (fetchErr) throw this.toErr(fetchErr)
    if (!stRow) throw new Error('Stok opname tidak ditemukan')

    const wasCompleted = stRow.status === 'completed'
    const shouldApplyStock = wasCompleted || Boolean(input.finalizeNow)
    const refTs = input.referenceAt ? this.normalizeReferenceAt(input.referenceAt) : stRow.reference_at

    const { data: allBalances, error: balErr } = await this.db
      .from('stock_balances')
      .select('variant_id, condition, quantity')
    if (balErr) throw this.toErr(balErr)
    const balMap = new Map<string, number>()
    for (const b of allBalances ?? []) {
      balMap.set(`${b.variant_id}:${b.condition}`, Number(b.quantity ?? 0))
    }

    const oldMap = new Map<string, { system_quantity: number; adjustment_quantity: number }>()
    for (const old of (stRow.stocktake_items ?? []) as Array<{ variant_id: string; condition: string; system_quantity: number; adjustment_quantity: number | null }>) {
      oldMap.set(`${old.variant_id}:${old.condition}`, {
        system_quantity: Number(old.system_quantity ?? 0),
        adjustment_quantity: Number(old.adjustment_quantity ?? 0),
      })
    }

    const { error: updErr } = await this.db
      .from('stocktakes')
      .update({
        officer_name: input.officerName,
        reference_at: refTs,
        status: shouldApplyStock ? 'completed' : stRow.status,
        finalized_at: shouldApplyStock ? nowIso : null,
        finalized_by: shouldApplyStock ? actorId : null,
      })
      .eq('id', id)
    if (updErr) throw this.toErr(updErr)

    const { error: delItemsErr } = await this.db.from('stocktake_items').delete().eq('stocktake_id', id)
    if (delItemsErr) throw this.toErr(delItemsErr)

    const nextRows = input.items.map((line) => {
      const key = `${line.variantId}:${line.condition}`
      const curBal = balMap.get(key) ?? 0
      const oldRec = oldMap.get(key)
      const physQty = Number(line.physicalQuantity)
      // Preserve pre-SO baseline for variance reporting when editing a completed SO
      const sysQty = wasCompleted && oldRec ? oldRec.system_quantity : curBal
      return {
        stocktake_id: id,
        variant_id: line.variantId,
        condition: line.condition,
        system_quantity: sysQty,
        physical_quantity: physQty,
        reason: line.reason || null,
        adjustment_quantity: physQty - sysQty,
        _deltaToApply: physQty - curBal,
      }
    })

    const { error: insItemsErr } = await this.db
      .from('stocktake_items')
      .insert(nextRows.map(({ _deltaToApply: _, ...dbRow }) => dbRow))
    if (insItemsErr) throw this.toErr(insItemsErr)

    if (shouldApplyStock) {
      for (const row of nextRows) {
        if (row._deltaToApply !== 0) {
          await this.applyStockMovementDirect(
            row.variant_id,
            row.condition,
            row._deltaToApply,
            'stocktake_adjustment',
            'stocktake',
            id,
            actorId,
            row.reason || `Revisi ${stRow.stocktake_no}`,
            nowIso,
          )
        }
      }
    }

    return id
  }

  async deleteStocktake(id: string): Promise<void> {
    const actorId = await this.resolveActorId()
    const { data: stRow, error: fetchErr } = await this.db
      .from('stocktakes')
      .select('id, stocktake_no, status, stocktake_items(variant_id, condition, adjustment_quantity)')
      .eq('id', id)
      .maybeSingle()
    if (fetchErr) throw this.toErr(fetchErr)
    if (!stRow) throw new Error('Stok opname tidak ditemukan')

    if (stRow.status === 'completed') {
      const items = (stRow.stocktake_items ?? []) as Array<{
        variant_id: string; condition: string; adjustment_quantity: number | null
      }>
      for (const old of items) {
        const adj = Number(old.adjustment_quantity ?? 0)
        if (adj === 0) continue
        const curBal = await this.getCurrentBalance(old.variant_id, old.condition)
        let reverseDelta = -adj
        if (curBal + reverseDelta < 0) reverseDelta = -curBal
        if (reverseDelta !== 0) {
          await this.applyStockMovementDirect(
            old.variant_id,
            old.condition,
            reverseDelta,
            'stocktake_adjustment',
            'stocktake',
            id,
            actorId,
            `Hapus ${stRow.stocktake_no} (pembalikan stok)`,
          )
        }
      }
    }

    const { error: delItemsErr } = await this.db.from('stocktake_items').delete().eq('stocktake_id', id)
    if (delItemsErr) throw this.toErr(delItemsErr)
    const { error: delErr } = await this.db.from('stocktakes').delete().eq('id', id)
    if (delErr) throw this.toErr(delErr)
  }

  async finalizeStocktake(stocktakeId: string): Promise<string> {
    const actorId = await this.resolveActorId()
    const nowIso = new Date().toISOString()
    const { data: stRow, error: fetchErr } = await this.db
      .from('stocktakes')
      .select('id, stocktake_no, status, stocktake_items(id, variant_id, condition, physical_quantity, reason)')
      .eq('id', stocktakeId)
      .maybeSingle()
    if (fetchErr) throw this.toErr(fetchErr)
    if (!stRow) throw new Error('Stok opname tidak ditemukan')
    if (stRow.status === 'completed') throw new Error('Stok opname sudah difinalisasi')

    const items = (stRow.stocktake_items ?? []) as Array<{
      id: string; variant_id: string; condition: string; physical_quantity: number; reason: string | null
    }>
    for (const line of items) {
      const curQty = await this.getCurrentBalance(line.variant_id, line.condition)
      const adjustment = Number(line.physical_quantity) - curQty
      if (adjustment !== 0) {
        await this.applyStockMovementDirect(
          line.variant_id,
          line.condition,
          adjustment,
          'stocktake_adjustment',
          'stocktake',
          stocktakeId,
          actorId,
          line.reason || `Penyesuaian ${stRow.stocktake_no}`,
          nowIso,
        )
      }
      await this.db
        .from('stocktake_items')
        .update({ system_quantity: curQty, adjustment_quantity: adjustment })
        .eq('id', line.id)
    }

    const { error: updErr } = await this.db
      .from('stocktakes')
      .update({ status: 'completed', finalized_at: nowIso, finalized_by: actorId })
      .eq('id', stocktakeId)
    if (updErr) throw this.toErr(updErr)
    return stocktakeId
  }

  async createReimbursement(input: ReimbursementInput): Promise<string> {
    const { data, error } = await this.db.rpc('create_reimbursement', {
      p_payload: input,
      p_actor: await this.resolveActorId(),
    })
    if (error) throw error
    return data as string
  }

  async getEmployeeLiabilities() {
    const { data, error } = await this.db
      .from('issuance_items')
      .select('*, issuances(id, transaction_no, issued_at, employee_id, employees(id, nik, name, position, department_id, departments(name))), item_variants(id, size, items(id, code, name, unit, return_required))')
      .order('created_at', { ascending: false })
      .limit(2000)
    if (error) throw error
    return (data ?? []).filter((row: Record<string, unknown>) => Number(row.quantity) - Number(row.returned_quantity) - Number(row.resolved_lost_quantity) > 0)
  }
}
