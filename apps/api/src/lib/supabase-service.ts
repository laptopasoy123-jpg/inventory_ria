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

  async getDashboard(month: number, year: number): Promise<Record<string, unknown>> {
    const [rpcRes, procsRes, unpaidRes] = await Promise.all([
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
    ])
    if (rpcRes.error) throw rpcRes.error
    const pendingPaymentAmount = (unpaidRes.data ?? []).reduce((acc, row) => acc + Number(row.remaining_amount || 0), 0)
    return {
      ...(rpcRes.data as Record<string, unknown>),
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
    const { error } = await this.db.from('departments').delete().eq('id', id)
    if (error) throw error
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
    const { error } = await this.db.from('funders').delete().eq('id', id)
    if (error) throw error
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
    const { error } = await this.db.from('employees').delete().eq('id', id)
    if (error) throw error
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
    await this.db.from('item_variants').delete().eq('item_id', id)
    const { error } = await this.db.from('items').delete().eq('id', id)
    if (error) throw error
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

    const ids = procs.map((p) => p.id)
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

    let result = procs.map((p) => ({ ...p, items: byProc.get(p.id) ?? [] }))
    if (variantId) {
      result = result.filter((p) =>
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
    const { data, error } = await this.db.rpc('update_procurement', {
      p_id: id,
      p_payload: input,
      p_actor: await this.resolveActorId(),
    })
    if (error) throw error
    return data as string
  }

  async updateProcurementStatus(id: string, status: string) {
    const { error } = await this.db.from('procurements').update({ status }).eq('id', id)
    if (error) throw error
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
    return (data ?? []).filter((row) => Number(row.quantity) - Number(row.returned_quantity) - Number(row.resolved_lost_quantity) > 0)
  }

  async createIssuance(input: IssuanceInput, idempotencyKey: string): Promise<string> {
    const { data, error } = await this.db.rpc('create_issuance', {
      p_payload: { ...input, idempotencyKey },
      p_actor: await this.resolveActorId(),
    })
    if (error) throw error
    return data as string
  }

  async updateIssuance(id: string, input: IssuanceInput): Promise<string> {
    const { data, error } = await this.db.rpc('update_issuance', {
      p_id: id,
      p_payload: input,
      p_actor: await this.resolveActorId(),
    })
    if (error) throw error
    return data as string
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
    return (data ?? []).filter((ret) =>
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

  async listStocktakes({ status }: { status?: string }) {
    let query = this.db
      .from('stocktakes')
      .select('*, stocktake_items(*, item_variants(size, items(code, name, unit)))')
      .order('created_at', { ascending: false })
      .limit(50)
    if (status && status !== 'all') query = query.eq('status', status)
    const { data, error } = await query
    if (error) throw error
    return data ?? []
  }

  async createStocktake(input: StocktakeCreateInput): Promise<string> {
    const { data, error } = await this.db.rpc('create_stocktake', {
      p_payload: input,
      p_actor: await this.resolveActorId(),
    })
    if (error) throw error
    return data as string
  }

  async updateStocktake(id: string, input: StocktakeCreateInput): Promise<string> {
    const { data, error } = await this.db.rpc('update_stocktake', {
      p_id: id,
      p_payload: input,
      p_actor: await this.resolveActorId(),
    })
    if (error) throw error
    return data as string
  }

  async finalizeStocktake(stocktakeId: string): Promise<string> {
    const { data, error } = await this.db.rpc('finalize_stocktake', {
      p_stocktake_id: stocktakeId,
      p_actor: await this.resolveActorId(),
    })
    if (error) throw error
    return data as string
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
      .select('*, issuances(transaction_no, issued_at, employees(id, nik, name, position, departments(name))), item_variants(size, items(code, name, unit, return_required))')
    if (error) throw error
    return (data ?? []).filter((row) => Number(row.quantity) - Number(row.returned_quantity) - Number(row.resolved_lost_quantity) > 0)
  }
}
