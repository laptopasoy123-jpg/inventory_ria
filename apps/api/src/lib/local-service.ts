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
  StockCondition,
  StocktakeCreateInput,
  SupplierInput,
} from '@inventaris/contracts'
import type { InventoryRow, InventoryService } from './service-types'

const STATE_KEY = '__local_inventory_db_clean_v1.json'

interface LocalState {
  seq: { opening: number; procurement: number; po?: number; purchase: number; issuance: number; return: number; stocktake: number; movement: number }
  idempotency: Record<string, string>
  categories: Array<{ id: string; code: string; name: string; created_at: string }>
  departments: Array<{ id: string; code: string; name: string; active: boolean; created_at: string }>
  suppliers: Array<{ id: string; code: string; name: string; vendor_type: 'supplier' | 'online_shop'; contact_name: string | null; phone: string | null; address: string | null; active: boolean; created_at: string }>
  funders: Array<{ id: string; name: string; phone: string | null; notes: string | null; active: boolean; created_at: string }>
  officers: Array<{ id: string; name: string; role_label: string; active: boolean; created_at: string }>
  employees: Array<{ id: string; nik: string; name: string; position: string; department_id: string; contract_status: string; created_at: string }>
  items: Array<{ id: string; code: string; name: string; category_id: string | null; specification: string | null; unit: string; minimum_stock: number; photo_key: string | null; return_required: boolean; active: boolean; created_at: string }>
  item_variants: Array<{ id: string; item_id: string; size: string; active: boolean; created_at: string }>
  stock_balances: Array<{ variant_id: string; condition: StockCondition; quantity: number; updated_at: string }>
  stock_movements: Array<{ id: number; variant_id: string; condition: StockCondition; quantity_delta: number; balance_after: number; movement_type: string; reference_type: string; reference_id: string; notes: string | null; occurred_at: string; created_by: string | null }>
  opening_stocks: Array<{ id: string; transaction_no: string; recorded_at: string; officer_name: string; notes: string | null; created_at: string; items: Array<{ id: string; variant_id: string; condition: StockCondition; quantity: number; notes: string | null }> }>
  procurements: Array<{
    id: string; procurement_no: string; procurement_date: string; expected_date: string | null; pr_number: string | null; po_number: string | null;
    department_id: string | null; supplier_id: string; reason: string; funding_source: 'company' | 'advanced'; payment_method: 'cash' | 'transfer';
    funder_id: string | null; total_amount: number; paid_amount: number; payment_status: 'unpaid' | 'partial' | 'paid';
    reimbursement_status: string | null; status: 'draft' | 'ordered' | 'partial' | 'completed' | 'cancelled'; document_key: string | null; notes: string | null; created_at: string;
    items: Array<{ id: string; procurement_id: string; variant_id: string; ordered_quantity: number; received_quantity: number; unit_price: number; notes: string | null }>
  }>
  procurement_payments: Array<{ id: string; procurement_id: string; paid_at: string; amount: number; payment_method: 'cash' | 'transfer'; payment_type: 'dp' | 'installment' | 'full' | 'reimbursement'; reference_no: string | null; proof_key: string | null; notes: string | null; created_at: string }>
  purchases: Array<{
    id: string; transaction_no: string; procurement_id: string | null; purchase_date: string; received_date: string; pr_number: string | null; request_number: string | null;
    po_number: string | null; delivery_note_number: string | null; invoice_number: string | null; reason: string; supplier_id: string;
    billing_proof_key: string | null; payment_proof_key: string | null; total_paid: number; funding_source: 'company' | 'advanced'; payment_method: 'cash' | 'transfer';
    funder_id: string | null; reimbursement_status: string | null; created_at: string;
    items: Array<{ id: string; procurement_item_id: string | null; variant_id: string; quantity: number; condition: StockCondition; serial_number: string | null; receiver_name: string; receipt_proof_key: string | null; notes: string | null }>
  }>
  issuances: Array<{
    id: string; transaction_no: string; issued_at: string; employee_id: string; officer_name: string; ba_key: string | null; handover_proof_key: string | null; notes: string | null; created_at: string;
    items: Array<{ id: string; issuance_id: string; variant_id: string; condition: 'new' | 'used_good'; quantity: number; returned_quantity: number; resolved_lost_quantity: number; purpose: string; notes: string | null }>
  }>
  returns: Array<{
    id: string; transaction_no: string; returned_at: string; employee_id: string; inspector_name: string; proof_key: string | null; created_at: string;
    items: Array<{ id: string; issuance_item_id: string; quantity: number; result: 'used_good' | 'maintenance' | 'damaged' | 'lost'; reusable?: boolean; reason: string | null; notes: string | null }>
  }>
  stocktakes: Array<{
    id: string; stocktake_no: string; reference_at: string; officer_name: string; status: 'draft' | 'pending_review' | 'completed';
    submitted_at: string | null; finalized_at: string | null; created_at: string;
    items: Array<{ id: string; variant_id: string; condition: StockCondition; system_quantity: number; physical_quantity: number; reason: string | null; adjustment_quantity: number | null }>
  }>
}

function createInitialState(): LocalState {
  return {
    seq: { opening: 0, procurement: 0, po: 0, purchase: 0, issuance: 0, return: 0, stocktake: 0, movement: 0 },
    idempotency: {},
    categories: [],
    departments: [],
    suppliers: [],
    funders: [],
    officers: [],
    employees: [],
    items: [],
    item_variants: [],
    stock_balances: [],
    stock_movements: [],
    opening_stocks: [],
    procurements: [],
    procurement_payments: [],
    purchases: [],
    issuances: [],
    returns: [],
    stocktakes: [],
  }
}

let memoryFallbackState: LocalState | null = null

export class LocalInventoryService implements InventoryService {
  constructor(private bucket?: R2Bucket) {}

  private async load(): Promise<LocalState> {
    const normalize = (s: LocalState) => {
      if (!s.officers) s.officers = []
      if (!s.seq.po) s.seq.po = s.procurements.length
      s.suppliers = s.suppliers.map((sup) => ({ ...sup, vendor_type: sup.vendor_type ?? 'supplier' }))
      return s
    }
    if (memoryFallbackState) {
      return structuredClone(normalize(memoryFallbackState))
    }
    if (this.bucket) {
      const obj = await this.bucket.get(STATE_KEY)
      if (obj) {
        const parsed = normalize(JSON.parse(await obj.text()) as LocalState)
        memoryFallbackState = parsed
        return structuredClone(parsed)
      }
    }
    const initial = createInitialState()
    await this.save(initial)
    return structuredClone(initial)
  }

  private async save(state: LocalState): Promise<void> {
    memoryFallbackState = structuredClone(state)
    if (this.bucket) {
      await this.bucket.put(STATE_KEY, JSON.stringify(state), {
        httpMetadata: { contentType: 'application/json' },
      })
    }
  }

  private nextDocNo(prefix: string, n: number): string {
    const ym = new Date().toISOString().slice(0, 7).replace('-', '')
    return `${prefix}-${ym}-${String(n).padStart(5, '0')}`
  }

  private toOccurredAt(dateInput: Date | string): string {
    const d = new Date(dateInput)
    const datePart = d.toISOString().slice(0, 10)
    const now = new Date()
    const localToday = `${now.getFullYear()}-${String(now.getMonth() + 1).padStart(2, '0')}-${String(now.getDate()).padStart(2, '0')}`
    const utcToday = now.toISOString().slice(0, 10)
    if (datePart === localToday || datePart === utcToday) {
      return now.toISOString()
    }
    return d.toISOString()
  }

  private applyMovement(
    state: LocalState,
    variantId: string,
    condition: StockCondition,
    delta: number,
    movementType: string,
    referenceType: string,
    referenceId: string,
    notes: string | null,
    occurredAt: string,
  ): number {
    if (delta === 0) throw new Error('Jumlah mutasi tidak boleh nol')
    let bal = state.stock_balances.find((b) => b.variant_id === variantId && b.condition === condition)
    if (!bal) {
      bal = { variant_id: variantId, condition, quantity: 0, updated_at: new Date().toISOString() }
      state.stock_balances.push(bal)
    }
    const nextQty = Number(bal.quantity) + Number(delta)
    if (nextQty < 0) {
      throw new Error(`Stok tidak mencukupi. Saldo ${bal.quantity}, perubahan ${delta}`)
    }
    bal.quantity = nextQty
    bal.updated_at = new Date().toISOString()
    state.seq.movement += 1
    state.stock_movements.push({
      id: state.seq.movement,
      variant_id: variantId,
      condition,
      quantity_delta: Number(delta),
      balance_after: nextQty,
      movement_type: movementType,
      reference_type: referenceType,
      reference_id: referenceId,
      notes,
      occurred_at: occurredAt,
      created_by: null,
    })
    return nextQty
  }

  private buildInventoryRows(state: LocalState): InventoryRow[] {
    const catMap = new Map(state.categories.map((c) => [c.id, c]))
    const itemMap = new Map(state.items.map((i) => [i.id, i]))
    const rows: InventoryRow[] = []

    for (const v of state.item_variants) {
      const item = itemMap.get(v.item_id)
      if (!item || !item.active || !v.active) continue
      const cat = item.category_id ? catMap.get(item.category_id) : null
      const bals = state.stock_balances.filter((b) => b.variant_id === v.id)
      const getQ = (c: StockCondition) => Number(bals.find((b) => b.condition === c)?.quantity ?? 0)
      const stock_new = getQ('new')
      const stock_used_good = getQ('used_good')
      const stock_quarantine = getQ('quarantine')
      const stock_damaged = getQ('damaged')
      const total_available = stock_new + stock_used_good
      const stock_status: 'safe' | 'low' | 'out' =
        total_available === 0 ? 'out' : total_available <= item.minimum_stock ? 'low' : 'safe'

      rows.push({
        variant_id: v.id,
        item_id: item.id,
        code: item.code,
        name: item.name,
        category_id: item.category_id ?? undefined,
        category_name: cat?.name ?? '-',
        specification: item.specification,
        size: v.size,
        unit: item.unit,
        minimum_stock: item.minimum_stock,
        return_required: item.return_required,
        photo_key: item.photo_key,
        stock_new,
        stock_used_good,
        stock_quarantine,
        stock_damaged,
        total_available,
        stock_status,
      })
    }
    return rows.sort((a, b) => a.name.localeCompare(b.name))
  }

  private enrichVariant(state: LocalState, variantId: string) {
    const v = state.item_variants.find((x) => x.id === variantId)
    const item = v ? state.items.find((i) => i.id === v.item_id) : null
    return {
      id: variantId,
      size: v?.size ?? '-',
      items: item ? { id: item.id, code: item.code, name: item.name, unit: item.unit, return_required: item.return_required, photo_key: item.photo_key ?? null } : null,
    }
  }

  private enrichProcurement(state: LocalState, p: LocalState['procurements'][number]) {
    const sup = state.suppliers.find((s) => s.id === p.supplier_id)
    const dept = p.department_id ? state.departments.find((d) => d.id === p.department_id) : null
    const funder = p.funder_id ? state.funders.find((f) => f.id === p.funder_id) : null
    const total_ordered = p.items.reduce((s, i) => s + Number(i.ordered_quantity), 0)
    const total_received = p.items.reduce((s, i) => s + Number(i.received_quantity), 0)
    const progress_percent = total_ordered > 0 ? Math.round((total_received / total_ordered) * 100) : 0
    const reimbursed_amount = state.procurement_payments
      .filter((pay) => pay.procurement_id === p.id && pay.payment_type === 'reimbursement')
      .reduce((s, pay) => s + Number(pay.amount), 0)
    return {
      ...p,
      supplier_name: sup?.name ?? '-',
      supplier_code: sup?.code ?? '-',
      vendor_type: sup?.vendor_type ?? 'supplier',
      department_name: dept?.name ?? null,
      funder_name: funder?.name ?? null,
      total_ordered,
      total_received,
      progress_percent,
      remaining_amount: Math.max(0, Number(p.total_amount) - Number(p.paid_amount)),
      reimbursed_amount,
      items: p.items.map((item) => ({ ...item, item_variants: this.enrichVariant(state, item.variant_id) })),
    }
  }

  async getDashboard(month: number, year: number, period: 'all' | 'year' | 'month' = 'all') {
    const state = await this.load()
    const inv = this.buildInventoryRows(state)
    const itemTypes = state.items.filter((i) => i.active).length
    const lowStockTypes = inv.filter((r) => r.stock_status === 'low').length
    const outStockTypes = inv.filter((r) => r.stock_status === 'out').length

    const unitTotalsMap = new Map<string, number>()
    for (const r of inv) {
      unitTotalsMap.set(r.unit, (unitTotalsMap.get(r.unit) ?? 0) + r.total_available)
    }
    const stockByUnit = [...unitTotalsMap.entries()].sort((a, b) => a[0].localeCompare(b[0])).map(([unit, quantity]) => ({ unit, quantity }))

    const start = period === 'year' ? new Date(year, 0, 1) : new Date(year, month - 1, 1)
    const end = period === 'year' ? new Date(year + 1, 0, 1) : new Date(year, month, 1)
    const inPeriod = (iso: string) => {
      if (period === 'all') return true
      const d = new Date(iso)
      return d >= start && d < end
    }
    const purchaseCount = state.purchases.filter((p) => inPeriod(p.received_date)).length

    const units = [...new Set(state.items.filter((i) => i.active).map((i) => i.unit))].sort()
    const variantUnit = new Map<string, string>()
    for (const v of state.item_variants) {
      const it = state.items.find((i) => i.id === v.item_id)
      if (it) variantUnit.set(v.id, it.unit)
    }

    const periodFlow = units.map((unit) => {
      let incoming = 0
      let outgoing = 0
      for (const sm of state.stock_movements) {
        if (variantUnit.get(sm.variant_id) !== unit) continue
        if (!inPeriod(sm.occurred_at)) continue
        if (sm.quantity_delta > 0 && (sm.movement_type === 'receipt' || sm.movement_type === 'opening_stock')) incoming += sm.quantity_delta
        if (sm.quantity_delta < 0 && sm.movement_type === 'issuance') outgoing += Math.abs(sm.quantity_delta)
      }
      return { unit, incoming, outgoing }
    })

    const monthLabels = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec']
    const monthlyFlow: Array<{ month: string; unit: string; incoming: number; outgoing: number }> = []
    for (let m = 0; m < 12; m++) {
      const ms = new Date(year, m, 1)
      const me = new Date(year, m + 1, 1)
      for (const unit of units) {
        let incoming = 0
        let outgoing = 0
        for (const sm of state.stock_movements) {
          if (variantUnit.get(sm.variant_id) !== unit) continue
          const d = new Date(sm.occurred_at)
          if (d < ms || d >= me) continue
          if (sm.quantity_delta > 0 && (sm.movement_type === 'receipt' || sm.movement_type === 'opening_stock')) incoming += sm.quantity_delta
          if (sm.quantity_delta < 0 && sm.movement_type === 'issuance') outgoing += Math.abs(sm.quantity_delta)
        }
        monthlyFlow.push({ month: monthLabels[m]!, unit, incoming, outgoing })
      }
    }

    const attentionItems = inv.filter((r) => r.stock_status !== 'safe').sort((a, b) => a.total_available - b.total_available).slice(0, 8)
    const activeProcurements = state.procurements
      .filter((p) => p.status === 'ordered' || p.status === 'partial')
      .map((p) => this.enrichProcurement(state, p))
      .slice(0, 6)
    const pendingPaymentAmount = state.procurements
      .filter((p) => p.status !== 'cancelled' && p.payment_status !== 'paid')
      .reduce((acc, p) => acc + Math.max(0, p.total_amount - p.paid_amount), 0)

    return {
      itemTypes,
      stockByUnit,
      lowStockTypes,
      outStockTypes,
      purchaseCount,
      periodFlow,
      monthlyFlow,
      attentionItems,
      activeProcurements,
      activeProcurementCount: activeProcurements.length,
      pendingPaymentAmount,
    }
  }

  async getMasterSummary() {
    const state = await this.load()
    const catMap = new Map(state.categories.map((c) => [c.id, c]))
    const deptMap = new Map(state.departments.map((d) => [d.id, d]))
    return {
      categories: [...state.categories].sort((a, b) => a.name.localeCompare(b.name)),
      departments: [...state.departments].sort((a, b) => a.name.localeCompare(b.name)),
      items: state.items.map((item) => ({
        ...item,
        categories: item.category_id ? (catMap.get(item.category_id) ?? null) : null,
        item_variants: state.item_variants.filter((v) => v.item_id === item.id),
      })).sort((a, b) => a.name.localeCompare(b.name)),
      variants: this.buildInventoryRows(state) as unknown as Record<string, unknown>[],
      employees: state.employees.map((e) => ({
        ...e,
        departments: deptMap.get(e.department_id) ?? null,
      })).sort((a, b) => a.name.localeCompare(b.name)),
      suppliers: [...state.suppliers].sort((a, b) => a.name.localeCompare(b.name)),
      funders: [...state.funders].sort((a, b) => a.name.localeCompare(b.name)),
      officers: [...(state.officers ?? [])].sort((a, b) => a.name.localeCompare(b.name)),
    }
  }

  async saveCategory(id: string | null, input: CategoryInput) {
    const state = await this.load()
    const dup = state.categories.find((c) => c.id !== id && (c.code.toLowerCase() === input.code.toLowerCase() || c.name.toLowerCase() === input.name.toLowerCase()))
    if (dup) throw new Error('Duplicate key: Kode atau nama kategori sudah ada')
    if (id) {
      const row = state.categories.find((c) => c.id === id)
      if (!row) throw new Error('Kategori tidak ditemukan')
      row.code = input.code
      row.name = input.name
      await this.save(state)
      return row
    }
    const row = { id: crypto.randomUUID(), code: input.code, name: input.name, created_at: new Date().toISOString() }
    state.categories.push(row)
    await this.save(state)
    return row
  }

  async deleteCategory(id: string) {
    const state = await this.load()
    if (state.items.some((i) => i.category_id === id)) throw new Error('Kategori masih digunakan oleh barang')
    state.categories = state.categories.filter((c) => c.id !== id)
    await this.save(state)
  }

  async saveDepartment(id: string | null, input: DepartmentInput) {
    const state = await this.load()
    const dup = state.departments.find((d) => d.id !== id && (d.code.toLowerCase() === input.code.toLowerCase() || d.name.toLowerCase() === input.name.toLowerCase()))
    if (dup) throw new Error('Duplicate key: Kode atau nama departemen sudah ada')
    if (id) {
      const row = state.departments.find((d) => d.id === id)
      if (!row) throw new Error('Departemen tidak ditemukan')
      Object.assign(row, input)
      await this.save(state)
      return row
    }
    const row = { id: crypto.randomUUID(), ...input, created_at: new Date().toISOString() }
    state.departments.push(row)
    await this.save(state)
    return row
  }

  async saveSupplier(id: string | null, input: SupplierInput) {
    const state = await this.load()
    const dup = state.suppliers.find((s) => s.id !== id && s.code.toLowerCase() === input.code.toLowerCase())
    if (dup) throw new Error('Duplicate key: Kode supplier / toko online sudah ada')
    const mapped = {
      code: input.code,
      name: input.name,
      vendor_type: input.vendorType ?? 'supplier',
      contact_name: input.contactName ?? null,
      phone: input.phone ?? null,
      address: input.address ?? null,
      active: input.active,
    }
    if (id) {
      const row = state.suppliers.find((s) => s.id === id)
      if (!row) throw new Error('Supplier tidak ditemukan')
      Object.assign(row, mapped)
      await this.save(state)
      return row
    }
    const row = { id: crypto.randomUUID(), ...mapped, created_at: new Date().toISOString() }
    state.suppliers.push(row)
    await this.save(state)
    return row
  }

  async saveFunder(id: string | null, input: FunderInput) {
    const state = await this.load()
    const mapped = { name: input.name, phone: input.phone ?? null, notes: input.notes ?? null, active: input.active }
    if (id) {
      const row = state.funders.find((f) => f.id === id)
      if (!row) throw new Error('Pihak penalang tidak ditemukan')
      Object.assign(row, mapped)
      await this.save(state)
      return row
    }
    const row = { id: crypto.randomUUID(), ...mapped, created_at: new Date().toISOString() }
    state.funders.push(row)
    await this.save(state)
    return row
  }

  async saveOfficer(id: string | null, input: OfficerInput) {
    const state = await this.load()
    if (!state.officers) state.officers = []
    const dup = state.officers.find((o) => o.id !== id && o.name.toLowerCase() === input.name.toLowerCase())
    if (dup) throw new Error('Duplicate key: Nama petugas sudah ada')
    const mapped = { name: input.name, role_label: input.roleLabel, active: input.active }
    if (id) {
      const row = state.officers.find((o) => o.id === id)
      if (!row) throw new Error('Petugas tidak ditemukan')
      Object.assign(row, mapped)
      await this.save(state)
      return row
    }
    const row = { id: crypto.randomUUID(), ...mapped, created_at: new Date().toISOString() }
    state.officers.push(row)
    await this.save(state)
    return row
  }

  async saveEmployee(id: string | null, input: EmployeeInput) {
    const state = await this.load()
    const dup = state.employees.find((e) => e.id !== id && e.nik.toLowerCase() === input.nik.toLowerCase())
    if (dup) throw new Error('Duplicate key: NIK karyawan sudah terdaftar')
    const mapped = {
      nik: input.nik,
      name: input.name,
      position: input.position,
      department_id: input.departmentId,
      contract_status: input.contractStatus,
    }
    if (id) {
      const row = state.employees.find((e) => e.id === id)
      if (!row) throw new Error('Karyawan tidak ditemukan')
      Object.assign(row, mapped)
      await this.save(state)
      return row
    }
    const row = { id: crypto.randomUUID(), ...mapped, created_at: new Date().toISOString() }
    state.employees.push(row)
    await this.save(state)
    return row
  }

  async saveItem(id: string | null, input: ItemInput) {
    const state = await this.load()
    const dup = state.items.find((i) => i.id !== id && i.code.toLowerCase() === input.code.toLowerCase())
    if (dup) throw new Error('Duplicate key: Kode barang sudah ada')

    const mapped = {
      code: input.code,
      name: input.name,
      category_id: input.categoryId ?? null,
      specification: input.specification ?? null,
      unit: input.unit,
      minimum_stock: input.minimumStock,
      photo_key: input.photoKey ?? null,
      return_required: input.returnRequired,
      active: input.active,
    }

    let itemId = id
    let savedItem: LocalState['items'][number]
    if (id) {
      const row = state.items.find((i) => i.id === id)
      if (!row) throw new Error('Barang tidak ditemukan')
      Object.assign(row, mapped)
      savedItem = row
    } else {
      itemId = crypto.randomUUID()
      savedItem = { id: itemId, ...mapped, created_at: new Date().toISOString() }
      state.items.push(savedItem)
    }

    const sizes = [...new Set(input.sizes.map((s) => s.trim()).filter(Boolean))]
    for (const size of sizes) {
      const existing = state.item_variants.find((v) => v.item_id === itemId && v.size.toLowerCase() === size.toLowerCase())
      if (existing) existing.active = true
      else state.item_variants.push({ id: crypto.randomUUID(), item_id: itemId!, size, active: true, created_at: new Date().toISOString() })
    }

    await this.save(state)
    return { ...savedItem, item_variants: state.item_variants.filter((v) => v.item_id === itemId) }
  }

  async deleteDepartment(id: string) {
    const state = await this.load()
    if (state.employees.some((e) => e.department_id === id)) {
      throw new Error('Departemen masih digunakan oleh data karyawan')
    }
    if (state.procurements.some((p) => p.department_id === id)) {
      throw new Error('Departemen masih digunakan oleh data pengadaan')
    }
    state.departments = state.departments.filter((d) => d.id !== id)
    await this.save(state)
  }

  async deleteSupplier(id: string) {
    const state = await this.load()
    if (state.procurements.some((p) => p.supplier_id === id)) {
      throw new Error('Supplier / toko online masih digunakan oleh pengadaan barang')
    }
    if (state.purchases.some((p) => p.supplier_id === id)) {
      throw new Error('Supplier / toko online masih digunakan oleh riwayat barang masuk')
    }
    state.suppliers = state.suppliers.filter((s) => s.id !== id)
    await this.save(state)
  }

  async deleteFunder(id: string) {
    const state = await this.load()
    if (state.procurements.some((p) => p.funder_id === id)) {
      throw new Error('Penyandang dana masih digunakan oleh pengadaan barang')
    }
    if (state.purchases.some((p) => p.funder_id === id)) {
      throw new Error('Penyandang dana masih digunakan oleh riwayat barang masuk')
    }
    state.funders = state.funders.filter((f) => f.id !== id)
    await this.save(state)
  }

  async deleteOfficer(id: string) {
    const state = await this.load()
    state.officers = state.officers.filter((o) => o.id !== id)
    await this.save(state)
  }

  async deleteEmployee(id: string) {
    const state = await this.load()
    if (state.issuances.some((i) => i.employee_id === id)) {
      throw new Error('Karyawan masih memiliki riwayat pengeluaran APD')
    }
    if (state.returns.some((r) => r.employee_id === id)) {
      throw new Error('Karyawan masih memiliki riwayat pengembalian APD')
    }
    state.employees = state.employees.filter((e) => e.id !== id)
    await this.save(state)
  }

  async deleteItem(id: string) {
    const state = await this.load()
    const variantIds = new Set(state.item_variants.filter((v) => v.item_id === id).map((v) => v.id))
    const usedInStock = state.stock_balances.some((b) => variantIds.has(b.variant_id) && b.quantity > 0)
    const usedInTx =
      state.stock_movements.some((m) => variantIds.has(m.variant_id)) ||
      state.procurements.some((p) => p.items.some((it) => variantIds.has(it.variant_id))) ||
      state.purchases.some((p) => p.items.some((it) => variantIds.has(it.variant_id))) ||
      state.issuances.some((i) => i.items.some((it) => variantIds.has(it.variant_id)))
    if (usedInStock || usedInTx) {
      throw new Error('Barang sudah memiliki stok atau riwayat transaksi sehingga tidak dapat dihapus')
    }
    state.stock_balances = state.stock_balances.filter((b) => !variantIds.has(b.variant_id))
    state.item_variants = state.item_variants.filter((v) => v.item_id !== id)
    state.items = state.items.filter((i) => i.id !== id)
    await this.save(state)
  }

  async listInventory({ page, limit, search, status, categoryId }: { page: number; limit: number; search?: string; status?: string; categoryId?: string }) {
    const state = await this.load()
    let rows = this.buildInventoryRows(state)
    if (search) {
      const q = search.toLowerCase()
      rows = rows.filter((r) =>
        r.code.toLowerCase().includes(q) ||
        r.name.toLowerCase().includes(q) ||
        r.category_name.toLowerCase().includes(q) ||
        r.size.toLowerCase().includes(q),
      )
    }
    if (status && status !== 'all') rows = rows.filter((r) => r.stock_status === status)
    if (categoryId && categoryId !== 'all') rows = rows.filter((r) => r.category_id === categoryId)

    const total = rows.length
    const start = (page - 1) * limit
    return {
      data: rows.slice(start, start + limit),
      pagination: { page, limit, total, totalPages: Math.max(1, Math.ceil(total / limit)) },
    }
  }

  async listMovements({ variantId, limit = 100 }: { variantId?: string; limit?: number }) {
    const state = await this.load()
    let rows = [...state.stock_movements]
    if (variantId) rows = rows.filter((m) => m.variant_id === variantId)
    return rows
      .sort((a, b) => new Date(b.occurred_at).getTime() - new Date(a.occurred_at).getTime() || b.id - a.id)
      .slice(0, limit)
      .map((m) => ({
        ...m,
        item_variants: this.enrichVariant(state, m.variant_id),
        profiles: { full_name: 'Petugas Gudang' },
      }))
  }

  async listOpeningStocks() {
    const state = await this.load()
    return [...state.opening_stocks]
      .sort((a, b) => new Date(b.created_at).getTime() - new Date(a.created_at).getTime())
      .map((o) => ({
        ...o,
        opening_stock_items: o.items.map((item) => ({ ...item, item_variants: this.enrichVariant(state, item.variant_id) })),
      }))
  }

  async createOpeningStock(input: OpeningStockInput, idempotencyKey: string): Promise<string> {
    const state = await this.load()
    if (state.idempotency[idempotencyKey]) return state.idempotency[idempotencyKey]!

    state.seq.opening += 1
    const id = crypto.randomUUID()
    const recordedAt = new Date(input.recordedAt).toISOString().slice(0, 10)
    const items = input.items.map((line) => {
      this.applyMovement(
        state,
        line.variantId,
        line.condition,
        line.quantity,
        'opening_stock',
        'opening_stock',
        id,
        line.notes || 'Input stok awal sebelumnya',
        this.toOccurredAt(input.recordedAt),
      )
      return { id: crypto.randomUUID(), variant_id: line.variantId, condition: line.condition, quantity: line.quantity, notes: line.notes ?? null }
    })

    state.opening_stocks.push({
      id,
      transaction_no: this.nextDocNo('SA', state.seq.opening),
      recorded_at: recordedAt,
      officer_name: input.officerName,
      notes: input.notes ?? null,
      created_at: new Date().toISOString(),
      items,
    })
    state.idempotency[idempotencyKey] = id
    await this.save(state)
    return id
  }

  async updateOpeningStock(id: string, input: OpeningStockInput): Promise<string> {
    const state = await this.load()
    const row = state.opening_stocks.find((o) => o.id === id)
    if (!row) throw new Error('Data stok awal tidak ditemukan')

    const netMap = new Map<string, { variantId: string; condition: StockCondition; delta: number; notes: string | null }>()
    for (const old of row.items) {
      const k = `${old.variant_id}:${old.condition}`
      const cur = netMap.get(k) || { variantId: old.variant_id, condition: old.condition, delta: 0, notes: old.notes }
      cur.delta -= Number(old.quantity)
      netMap.set(k, cur)
    }
    for (const line of input.items) {
      const k = `${line.variantId}:${line.condition}`
      const cur = netMap.get(k) || { variantId: line.variantId, condition: line.condition, delta: 0, notes: line.notes ?? null }
      cur.delta += Number(line.quantity)
      cur.notes = line.notes ?? cur.notes
      netMap.set(k, cur)
    }

    for (const entry of netMap.values()) {
      if (entry.delta !== 0) {
        this.applyMovement(state, entry.variantId, entry.condition, entry.delta, 'opening_stock', 'opening_stock', id, entry.notes || 'Revisi stok awal', this.toOccurredAt(input.recordedAt))
      }
    }

    row.recorded_at = new Date(input.recordedAt).toISOString().slice(0, 10)
    row.officer_name = input.officerName
    row.notes = input.notes ?? null
    row.items = input.items.map((line) => ({
      id: crypto.randomUUID(),
      variant_id: line.variantId,
      condition: line.condition,
      quantity: line.quantity,
      notes: line.notes ?? null,
    }))
    await this.save(state)
    return id
  }

  async transferCondition(input: ConditionTransferInput): Promise<string> {
    if (input.fromCondition === input.toCondition) throw new Error('Kondisi asal dan tujuan tidak boleh sama')
    const state = await this.load()
    const refId = crypto.randomUUID()
    const now = new Date().toISOString()
    const notes = input.notes || 'Tindak lanjut karantina / pindah kondisi'
    this.applyMovement(state, input.variantId, input.fromCondition, -input.quantity, 'condition_transfer', 'condition_transfer', refId, notes, now)
    this.applyMovement(state, input.variantId, input.toCondition, input.quantity, 'condition_transfer', 'condition_transfer', refId, notes, now)
    await this.save(state)
    return refId
  }

  async listProcurements({ status, paymentStatus, search, variantId, onlyPendingReceipt }: {
    status?: string; paymentStatus?: string; search?: string; variantId?: string; onlyPendingReceipt?: boolean
  }) {
    const state = await this.load()
    let list = state.procurements.map((p) => this.enrichProcurement(state, p))
    if (onlyPendingReceipt) list = list.filter((p) => p.status === 'ordered' || p.status === 'partial')
    else if (status && status !== 'all') list = list.filter((p) => p.status === status)
    if (paymentStatus && paymentStatus !== 'all') list = list.filter((p) => p.payment_status === paymentStatus)
    if (search) {
      const q = search.toLowerCase()
      list = list.filter((p) =>
        p.procurement_no.toLowerCase().includes(q) ||
        (p.po_number || '').toLowerCase().includes(q) ||
        (p.pr_number || '').toLowerCase().includes(q) ||
        p.supplier_name.toLowerCase().includes(q) ||
        p.reason.toLowerCase().includes(q) ||
        p.items.some((it) => (it.item_variants.items?.name || '').toLowerCase().includes(q)),
      )
    }
    if (variantId) {
      list = list.filter((p) => p.items.some((it) => it.variant_id === variantId && it.ordered_quantity > it.received_quantity))
    }
    return list.sort((a, b) => new Date(b.created_at).getTime() - new Date(a.created_at).getTime())
  }

  async getProcurement(id: string) {
    const state = await this.load()
    const proc = state.procurements.find((p) => p.id === id)
    if (!proc) throw new Error('Pengadaan tidak ditemukan')
    const receipts = state.purchases
      .filter((p) => p.procurement_id === id)
      .map((r) => ({
        ...r,
        purchase_items: r.items.map((it) => ({ ...it, item_variants: this.enrichVariant(state, it.variant_id) })),
      }))
    const payments = state.procurement_payments.filter((pay) => pay.procurement_id === id)
    return { ...this.enrichProcurement(state, proc), receipts, payments }
  }

  async createProcurement(input: ProcurementInput, idempotencyKey: string): Promise<string> {
    const state = await this.load()
    if (state.idempotency[idempotencyKey]) return state.idempotency[idempotencyKey]!

    state.seq.procurement += 1
    state.seq.po = (state.seq.po ?? state.procurements.length) + 1
    const id = crypto.randomUUID()

    const mergedLines = new Map<string, { variantId: string; orderedQuantity: number; unitPrice: number; notes: string | null }>()
    for (const raw of input.items) {
      const prev = mergedLines.get(raw.variantId)
      if (prev) {
        prev.orderedQuantity += raw.orderedQuantity
        if (raw.unitPrice > 0) prev.unitPrice = raw.unitPrice
        if (raw.notes) prev.notes = prev.notes ? `${prev.notes}; ${raw.notes}` : raw.notes
      } else {
        mergedLines.set(raw.variantId, {
          variantId: raw.variantId,
          orderedQuantity: raw.orderedQuantity,
          unitPrice: raw.unitPrice || 0,
          notes: raw.notes ?? null,
        })
      }
    }
    const consolidatedItems = [...mergedLines.values()]
    const calcTotal = consolidatedItems.reduce((s, item) => s + item.orderedQuantity * item.unitPrice, 0)
    const totalAmount = input.totalAmount && input.totalAmount > 0 ? input.totalAmount : calcTotal
    const autoPo = input.poNumber?.trim() || this.nextDocNo('PO', state.seq.po)

    state.procurements.push({
      id,
      procurement_no: this.nextDocNo('PGD', state.seq.procurement),
      procurement_date: new Date(input.procurementDate).toISOString().slice(0, 10),
      expected_date: input.expectedDate ? new Date(input.expectedDate).toISOString().slice(0, 10) : null,
      pr_number: input.prNumber ?? null,
      po_number: autoPo,
      department_id: input.departmentId ?? null,
      supplier_id: input.supplierId,
      reason: input.reason,
      funding_source: input.fundingSource,
      payment_method: input.paymentMethod,
      funder_id: input.funderId ?? null,
      total_amount: totalAmount,
      paid_amount: 0,
      payment_status: 'unpaid',
      reimbursement_status: input.fundingSource === 'advanced' ? 'not_submitted' : null,
      status: 'ordered',
      document_key: input.documentKey ?? null,
      notes: input.notes ?? null,
      created_at: new Date().toISOString(),
      items: consolidatedItems.map((item) => ({
        id: crypto.randomUUID(),
        procurement_id: id,
        variant_id: item.variantId,
        ordered_quantity: item.orderedQuantity,
        received_quantity: 0,
        unit_price: item.unitPrice,
        notes: item.notes,
      })),
    })

    state.idempotency[idempotencyKey] = id
    await this.save(state)
    return id
  }

  async updateProcurement(id: string, input: ProcurementInput): Promise<string> {
    const state = await this.load()
    const proc = state.procurements.find((p) => p.id === id)
    if (!proc) throw new Error('Pengadaan tidak ditemukan')

    const calcTotal = input.items.reduce((s, item) => s + item.orderedQuantity * (item.unitPrice || 0), 0)
    const totalAmount = input.totalAmount && input.totalAmount > 0 ? input.totalAmount : calcTotal
    if (totalAmount < proc.paid_amount) {
      throw new Error(`Total pengadaan tidak boleh lebih kecil dari jumlah yang sudah dibayar (${proc.paid_amount})`)
    }

    const oldMap = new Map(proc.items.map((it) => [it.id, it]))
    const nextItems: LocalState['procurements'][number]['items'] = []
    for (const line of input.items) {
      const existing = line.id ? oldMap.get(line.id) : undefined
      if (existing) {
        if (line.orderedQuantity < existing.received_quantity) {
          throw new Error(`Jumlah dipesan (${line.orderedQuantity}) tidak boleh kurang dari yang sudah diterima (${existing.received_quantity})`)
        }
        nextItems.push({
          ...existing,
          variant_id: line.variantId,
          ordered_quantity: line.orderedQuantity,
          unit_price: line.unitPrice || 0,
          notes: line.notes ?? null,
        })
      } else {
        nextItems.push({
          id: crypto.randomUUID(),
          procurement_id: id,
          variant_id: line.variantId,
          ordered_quantity: line.orderedQuantity,
          received_quantity: 0,
          unit_price: line.unitPrice || 0,
          notes: line.notes ?? null,
        })
      }
    }

    const keptIds = new Set(nextItems.map((it) => it.id))
    for (const old of proc.items) {
      if (!keptIds.has(old.id) && old.received_quantity > 0) {
        throw new Error('Item yang sudah memiliki penerimaan barang tidak dapat dihapus')
      }
    }

    proc.procurement_date = new Date(input.procurementDate).toISOString().slice(0, 10)
    proc.expected_date = input.expectedDate ? new Date(input.expectedDate).toISOString().slice(0, 10) : null
    proc.pr_number = input.prNumber ?? null
    proc.po_number = input.poNumber ?? null
    proc.department_id = input.departmentId ?? null
    proc.supplier_id = input.supplierId
    proc.reason = input.reason
    proc.funding_source = input.fundingSource
    proc.payment_method = input.paymentMethod
    proc.funder_id = input.funderId ?? null
    proc.total_amount = totalAmount
    proc.payment_status = proc.paid_amount >= totalAmount && totalAmount > 0 ? 'paid' : proc.paid_amount > 0 ? 'partial' : 'unpaid'
    proc.reimbursement_status = input.fundingSource === 'advanced' ? (proc.reimbursement_status || 'not_submitted') : null
    proc.notes = input.notes ?? null
    proc.items = nextItems

    const totalOrd = nextItems.reduce((s, i) => s + i.ordered_quantity, 0)
    const totalRec = nextItems.reduce((s, i) => s + i.received_quantity, 0)
    if (proc.status !== 'cancelled') {
      proc.status = totalRec >= totalOrd && totalOrd > 0 ? 'completed' : totalRec > 0 ? 'partial' : 'ordered'
    }

    await this.save(state)
    return id
  }

  async updateProcurementStatus(id: string, status: string, cancelNote?: string) {
    const state = await this.load()
    const proc = state.procurements.find((p) => p.id === id)
    if (!proc) throw new Error('Pengadaan tidak ditemukan')
    if (status === 'cancelled' && proc.status === 'completed') {
      throw new Error('Pengadaan yang sudah terpenuhi 100% tidak dapat dibatalkan')
    }

    let nextStatus = status
    if (status !== 'cancelled') {
      const totalOrdered = proc.items.reduce((s, i) => s + Number(i.ordered_quantity || 0), 0)
      const totalReceived = proc.items.reduce((s, i) => s + Number(i.received_quantity || 0), 0)
      if (totalOrdered > 0 && totalReceived >= totalOrdered) {
        nextStatus = 'completed'
      } else if (totalReceived > 0) {
        nextStatus = 'partial'
      } else {
        nextStatus = 'ordered'
      }
    }

    proc.status = nextStatus as LocalState['procurements'][number]['status']
    const cleanedPrevNotes = String(proc.notes || '')
      .replace(/(?:\s*·\s*)?\[(?:Alasan Cancel|Batal Cancel):[^\]]*\]/g, '')
      .replace(/^\s*·\s*/, '')
      .trim()

    if (status === 'cancelled') {
      if (cancelNote?.trim()) {
        const tag = `[Alasan Cancel: ${cancelNote.trim()}]`
        proc.notes = cleanedPrevNotes ? `${cleanedPrevNotes} · ${tag}` : tag
      }
    } else {
      if (cancelNote?.trim()) {
        const tag = `[Batal Cancel: ${cancelNote.trim()}]`
        proc.notes = cleanedPrevNotes ? `${cleanedPrevNotes} · ${tag}` : tag
      } else {
        proc.notes = cleanedPrevNotes || null
      }
    }
    await this.save(state)
  }

  async deleteOpeningStock(id: string): Promise<void> {
    const state = await this.load()
    const idx = state.opening_stocks.findIndex((o) => o.id === id)
    if (idx === -1) throw new Error('Data stok awal tidak ditemukan')
    const rec = state.opening_stocks[idx]!
    for (const line of rec.items) {
      this.applyMovement(state, line.variant_id, line.condition, -line.quantity, 'opening_stock', 'opening_stock', id, `Hapus stok awal ${rec.transaction_no}`, new Date().toISOString())
    }
    state.opening_stocks.splice(idx, 1)
    await this.save(state)
  }

  async deleteProcurement(id: string): Promise<void> {
    const state = await this.load()
    const idx = state.procurements.findIndex((p) => p.id === id)
    if (idx === -1) throw new Error('Pengadaan tidak ditemukan')
    const proc = state.procurements[idx]!
    const procItemIds = new Set(proc.items.map((i) => i.id))
    for (const pur of state.purchases) {
      if (pur.procurement_id === id) pur.procurement_id = null
      for (const it of pur.items) {
        if (it.procurement_item_id && procItemIds.has(it.procurement_item_id)) it.procurement_item_id = null
      }
    }
    state.procurement_payments = state.procurement_payments.filter((pay) => pay.procurement_id !== id)
    state.procurements.splice(idx, 1)
    await this.save(state)
  }

  async deleteProcurementPayment(id: string): Promise<void> {
    const state = await this.load()
    const idx = state.procurement_payments.findIndex((p) => p.id === id)
    if (idx === -1) throw new Error('Data pembayaran tidak ditemukan')
    const pay = state.procurement_payments[idx]!
    state.procurement_payments.splice(idx, 1)
    const proc = state.procurements.find((p) => p.id === pay.procurement_id)
    if (proc) {
      const paid = state.procurement_payments.filter((x) => x.procurement_id === proc.id && x.payment_type !== 'reimbursement').reduce((s, x) => s + x.amount, 0)
      const reimb = state.procurement_payments.filter((x) => x.procurement_id === proc.id && x.payment_type === 'reimbursement').reduce((s, x) => s + x.amount, 0)
      proc.paid_amount = paid
      proc.payment_status = paid >= proc.total_amount && proc.total_amount > 0 ? 'paid' : paid > 0 ? 'partial' : 'unpaid'
      if (proc.funding_source === 'advanced') {
        proc.reimbursement_status = reimb >= proc.total_amount ? 'paid' : reimb > 0 ? 'partially_paid' : 'not_submitted'
      }
    }
    await this.save(state)
  }

  async deletePurchaseReceipt(id: string): Promise<void> {
    const state = await this.load()
    const idx = state.purchases.findIndex((p) => p.id === id)
    if (idx === -1) throw new Error('Transaksi barang masuk tidak ditemukan')
    const pur = state.purchases[idx]!
    for (const line of pur.items) {
      this.applyMovement(state, line.variant_id, line.condition, -line.quantity, 'receipt', 'purchase', id, `Hapus barang masuk ${pur.transaction_no}`, new Date().toISOString())
      if (line.procurement_item_id) {
        for (const proc of state.procurements) {
          const pi = proc.items.find((x) => x.id === line.procurement_item_id)
          if (pi) pi.received_quantity = Math.max(0, pi.received_quantity - line.quantity)
        }
      }
    }
    state.purchases.splice(idx, 1)
    if (pur.procurement_id) {
      const proc = state.procurements.find((p) => p.id === pur.procurement_id)
      if (proc && proc.status !== 'cancelled') {
        const totalOrd = proc.items.reduce((s, i) => s + i.ordered_quantity, 0)
        const totalRec = proc.items.reduce((s, i) => s + i.received_quantity, 0)
        proc.status = totalRec >= totalOrd && totalOrd > 0 ? 'completed' : totalRec > 0 ? 'partial' : 'ordered'
      }
    }
    await this.save(state)
  }

  async deleteIssuance(id: string): Promise<void> {
    const state = await this.load()
    const idx = state.issuances.findIndex((i) => i.id === id)
    if (idx === -1) throw new Error('Transaksi barang keluar tidak ditemukan')
    const iss = state.issuances[idx]!
    const issItemMap = new Map(iss.items.map((it) => [it.id, it]))
    for (const ret of [...state.returns]) {
      const removed = ret.items.filter((ri) => issItemMap.has(ri.issuance_item_id))
      if (!removed.length) continue
      for (const ri of removed) {
        const parent = issItemMap.get(ri.issuance_item_id)!
        if (ri.result !== 'lost') {
          const targetCond: StockCondition | null =
            ri.result === 'used_good' ? 'used_good'
              : ri.result === 'maintenance' ? 'quarantine'
                : ri.result === 'damaged' && ri.reusable ? 'used_good'
                  : null
          if (targetCond) {
            const bal = state.stock_balances.find((b) => b.variant_id === parent.variant_id && b.condition === targetCond)
            const cur = Number(bal?.quantity ?? 0)
            const delta = -Math.min(cur, ri.quantity)
            if (delta !== 0) this.applyMovement(state, parent.variant_id, targetCond, delta, 'return', 'return', ret.id, `Hapus barang keluar ${iss.transaction_no}`, new Date().toISOString())
          }
        }
      }
      ret.items = ret.items.filter((ri) => !issItemMap.has(ri.issuance_item_id))
    }
    state.returns = state.returns.filter((r) => r.items.length > 0)
    for (const line of iss.items) {
      this.applyMovement(state, line.variant_id, line.condition, line.quantity, 'issuance', 'issuance', id, `Hapus barang keluar ${iss.transaction_no}`, new Date().toISOString())
    }
    state.issuances.splice(idx, 1)
    await this.save(state)
  }

  async deleteReturn(id: string): Promise<void> {
    const state = await this.load()
    const idx = state.returns.findIndex((r) => r.id === id)
    if (idx === -1) throw new Error('Transaksi pengembalian tidak ditemukan')
    const ret = state.returns[idx]!
    for (const old of ret.items) {
      let foundLine: LocalState['issuances'][number]['items'][number] | null = null
      for (const iss of state.issuances) {
        const m = iss.items.find((x) => x.id === old.issuance_item_id)
        if (m) { foundLine = m; break }
      }
      if (!foundLine) continue
      if (old.result === 'lost') {
        foundLine.resolved_lost_quantity = Math.max(0, foundLine.resolved_lost_quantity - old.quantity)
      } else {
        foundLine.returned_quantity = Math.max(0, foundLine.returned_quantity - old.quantity)
        const targetCond: StockCondition | null =
          old.result === 'used_good' ? 'used_good'
            : old.result === 'maintenance' ? 'quarantine'
              : old.result === 'damaged' && old.reusable === true ? 'used_good'
                : null
        if (targetCond) {
          this.applyMovement(state, foundLine.variant_id, targetCond, -old.quantity, 'return', 'return', id, `Hapus pengembalian ${ret.transaction_no}`, new Date().toISOString())
        }
      }
    }
    state.returns.splice(idx, 1)
    await this.save(state)
  }

  async createProcurementPayment(input: ProcurementPaymentInput): Promise<string> {
    const state = await this.load()
    const proc = state.procurements.find((p) => p.id === input.procurementId)
    if (!proc) throw new Error('Pengadaan tidak ditemukan')

    if (input.paymentType === 'reimbursement') {
      if (proc.funding_source !== 'advanced') throw new Error('Reimbursement hanya untuk dana talangan')
      const already = state.procurement_payments
        .filter((pay) => pay.procurement_id === proc.id && pay.payment_type === 'reimbursement')
        .reduce((s, pay) => s + pay.amount, 0)
      const rem = proc.total_amount - already
      if (input.amount > rem) throw new Error(`Jumlah reimbursement melebihi sisa ${rem}`)
      proc.reimbursement_status = input.amount === rem ? 'paid' : 'partially_paid'
    } else {
      const rem = proc.total_amount - proc.paid_amount
      if (input.amount > rem) throw new Error(`Jumlah pembayaran melebihi sisa tagihan ${rem}`)
      proc.paid_amount += input.amount
      proc.payment_status = proc.paid_amount >= proc.total_amount ? 'paid' : 'partial'
    }

    const id = crypto.randomUUID()
    state.procurement_payments.push({
      id,
      procurement_id: proc.id,
      paid_at: new Date(input.paidAt).toISOString().slice(0, 10),
      amount: input.amount,
      payment_method: input.paymentMethod,
      payment_type: input.paymentType,
      reference_no: input.referenceNo ?? null,
      proof_key: input.proofKey ?? null,
      notes: input.notes ?? null,
      created_at: new Date().toISOString(),
    })

    await this.save(state)
    return id
  }

  async updateProcurementPayment(id: string, input: ProcurementPaymentInput): Promise<string> {
    const state = await this.load()
    const pay = state.procurement_payments.find((p) => p.id === id)
    if (!pay) throw new Error('Data pembayaran tidak ditemukan')
    const proc = state.procurements.find((p) => p.id === pay.procurement_id)
    if (!proc) throw new Error('Pengadaan tidak ditemukan')

    pay.paid_at = new Date(input.paidAt).toISOString().slice(0, 10)
    pay.amount = input.amount
    pay.payment_method = input.paymentMethod
    pay.payment_type = input.paymentType
    pay.reference_no = input.referenceNo ?? null
    pay.proof_key = input.proofKey ?? pay.proof_key
    pay.notes = input.notes ?? null

    const newPaid = state.procurement_payments
      .filter((p) => p.procurement_id === proc.id && p.payment_type !== 'reimbursement')
      .reduce((s, p) => s + Number(p.amount), 0)
    if (newPaid > proc.total_amount) {
      throw new Error(`Total pembayaran (${newPaid}) melebihi total tagihan (${proc.total_amount})`)
    }

    const newReimb = state.procurement_payments
      .filter((p) => p.procurement_id === proc.id && p.payment_type === 'reimbursement')
      .reduce((s, p) => s + Number(p.amount), 0)
    if (proc.funding_source === 'advanced' && newReimb > proc.total_amount) {
      throw new Error(`Total reimbursement melebihi nilai pengadaan (${proc.total_amount})`)
    }

    proc.paid_amount = newPaid
    proc.payment_status = newPaid >= proc.total_amount && proc.total_amount > 0 ? 'paid' : newPaid > 0 ? 'partial' : 'unpaid'
    if (proc.funding_source === 'advanced') {
      proc.reimbursement_status = newReimb >= proc.total_amount ? 'paid' : newReimb > 0 ? 'partially_paid' : 'not_submitted'
    }

    await this.save(state)
    return id
  }

  async listPayments() {
    const state = await this.load()
    return [...state.procurement_payments]
      .sort((a, b) => new Date(b.paid_at).getTime() - new Date(a.paid_at).getTime())
      .map((pay) => {
        const proc = state.procurements.find((p) => p.id === pay.procurement_id)
        const sup = proc ? state.suppliers.find((s) => s.id === proc.supplier_id) : null
        return {
          ...pay,
          procurements: proc ? {
            procurement_no: proc.procurement_no,
            po_number: proc.po_number,
            total_amount: proc.total_amount,
            funding_source: proc.funding_source,
            suppliers: { name: sup?.name ?? '-' },
          } : null,
        }
      })
  }

  async listPurchases({ fundingSource, search }: { fundingSource?: string; search?: string }) {
    const state = await this.load()
    let rows = [...state.purchases]
    if (fundingSource && fundingSource !== 'all') rows = rows.filter((p) => p.funding_source === fundingSource)
    if (search) {
      const q = search.toLowerCase()
      rows = rows.filter((p) =>
        p.transaction_no.toLowerCase().includes(q) ||
        (p.po_number || '').toLowerCase().includes(q) ||
        (p.delivery_note_number || '').toLowerCase().includes(q) ||
        p.reason.toLowerCase().includes(q),
      )
    }
    return rows
      .sort((a, b) => new Date(b.received_date).getTime() - new Date(a.received_date).getTime())
      .map((p) => {
        const sup = state.suppliers.find((s) => s.id === p.supplier_id)
        const proc = p.procurement_id ? state.procurements.find((pr) => pr.id === p.procurement_id) : null
        return {
          ...p,
          suppliers: sup ? { name: sup.name, code: sup.code, vendor_type: sup.vendor_type } : null,
          procurements: proc ? { procurement_no: proc.procurement_no, po_number: proc.po_number } : null,
          purchase_items: p.items.map((it) => ({ ...it, item_variants: this.enrichVariant(state, it.variant_id) })),
        }
      })
  }

  async createPurchaseReceipt(input: PurchaseInput, idempotencyKey: string): Promise<string> {
    const state = await this.load()
    if (state.idempotency[idempotencyKey]) return state.idempotency[idempotencyKey]!

    let proc: LocalState['procurements'][number] | undefined
    if (input.procurementId) {
      proc = state.procurements.find((p) => p.id === input.procurementId)
      if (!proc) throw new Error('Pengadaan barang tidak ditemukan')
      if (proc.status === 'cancelled' || proc.status === 'completed') {
        throw new Error(`Pengadaan ${proc.procurement_no} sudah berstatus ${proc.status}`)
      }
    }

    state.seq.purchase += 1
    const purchaseId = crypto.randomUUID()
    const receivedDate = new Date(input.receivedDate).toISOString().slice(0, 10)
    const purchaseDate = input.purchaseDate ? new Date(input.purchaseDate).toISOString().slice(0, 10) : (proc?.procurement_date ?? receivedDate)

    const items: LocalState['purchases'][number]['items'] = []
    for (const line of input.items) {
      if (line.procurementItemId) {
        const procItem = proc?.items.find((pi) => pi.id === line.procurementItemId)
        if (!procItem) throw new Error('Item pengadaan tidak ditemukan')
        const remaining = procItem.ordered_quantity - procItem.received_quantity
        if (line.quantity > remaining) {
          throw new Error(`Jumlah diterima melebihi sisa pengadaan (${remaining} tersisa)`)
        }
        procItem.received_quantity += line.quantity
      }
      this.applyMovement(
        state,
        line.variantId,
        line.condition,
        line.quantity,
        'receipt',
        'purchase',
        purchaseId,
        line.notes || (proc ? `Penerimaan ${proc.procurement_no}` : 'Penerimaan pembelian'),
        this.toOccurredAt(input.receivedDate),
      )
      items.push({
        id: crypto.randomUUID(),
        procurement_item_id: line.procurementItemId ?? null,
        variant_id: line.variantId,
        quantity: line.quantity,
        condition: line.condition,
        serial_number: line.serialNumber ?? null,
        receiver_name: line.receiverName,
        receipt_proof_key: line.receiptProofKey ?? null,
        notes: line.notes ?? null,
      })
    }

    if (proc) {
      const totalOrd = proc.items.reduce((s, i) => s + i.ordered_quantity, 0)
      const totalRec = proc.items.reduce((s, i) => s + i.received_quantity, 0)
      proc.status = totalRec >= totalOrd && totalOrd > 0 ? 'completed' : totalRec > 0 ? 'partial' : 'ordered'
    }

    state.purchases.push({
      id: purchaseId,
      transaction_no: this.nextDocNo('PB', state.seq.purchase),
      procurement_id: proc?.id ?? null,
      purchase_date: purchaseDate,
      received_date: receivedDate,
      pr_number: input.prNumber ?? proc?.pr_number ?? null,
      request_number: input.requestNumber ?? null,
      po_number: input.poNumber ?? proc?.po_number ?? null,
      delivery_note_number: input.deliveryNoteNumber ?? null,
      invoice_number: input.invoiceNumber ?? null,
      reason: input.reason || proc?.reason || 'Penerimaan barang',
      supplier_id: input.supplierId || proc!.supplier_id,
      billing_proof_key: input.billingProofKey ?? null,
      payment_proof_key: input.paymentProofKey ?? null,
      total_paid: input.totalPaid ?? 0,
      funding_source: input.fundingSource ?? proc?.funding_source ?? 'company',
      payment_method: input.paymentMethod ?? proc?.payment_method ?? 'transfer',
      funder_id: input.funderId ?? proc?.funder_id ?? null,
      reimbursement_status: (input.fundingSource ?? proc?.funding_source) === 'advanced' ? 'not_submitted' : null,
      created_at: new Date().toISOString(),
      items,
    })

    state.idempotency[idempotencyKey] = purchaseId
    await this.save(state)
    return purchaseId
  }

  async updatePurchaseReceipt(id: string, input: PurchaseInput): Promise<string> {
    const state = await this.load()
    const pur = state.purchases.find((p) => p.id === id)
    if (!pur) throw new Error('Transaksi barang masuk tidak ditemukan')

    const netMap = new Map<string, { variantId: string; condition: StockCondition; delta: number; notes: string | null }>()
    for (const old of pur.items) {
      if (old.procurement_item_id && pur.procurement_id) {
        const oldProc = state.procurements.find((p) => p.id === pur.procurement_id)
        const oldPi = oldProc?.items.find((pi) => pi.id === old.procurement_item_id)
        if (oldPi) oldPi.received_quantity = Math.max(0, oldPi.received_quantity - old.quantity)
      }
      const k = `${old.variant_id}:${old.condition}`
      const cur = netMap.get(k) || { variantId: old.variant_id, condition: old.condition, delta: 0, notes: old.notes }
      cur.delta -= Number(old.quantity)
      netMap.set(k, cur)
    }

    if (pur.procurement_id) {
      const prevProc = state.procurements.find((p) => p.id === pur.procurement_id)
      if (prevProc) {
        const totalOrd = prevProc.items.reduce((s, i) => s + i.ordered_quantity, 0)
        const totalRec = prevProc.items.reduce((s, i) => s + i.received_quantity, 0)
        prevProc.status = totalRec >= totalOrd && totalOrd > 0 ? 'completed' : totalRec > 0 ? 'partial' : 'ordered'
      }
    }

    const nextProc = input.procurementId ? state.procurements.find((p) => p.id === input.procurementId) : undefined
    if (input.procurementId && !nextProc) throw new Error('Pengadaan barang tidak ditemukan')

    const items: LocalState['purchases'][number]['items'] = []
    for (const line of input.items) {
      if (line.procurementItemId) {
        const pi = nextProc?.items.find((x) => x.id === line.procurementItemId)
        if (!pi) throw new Error('Item pengadaan tidak ditemukan')
        const rem = pi.ordered_quantity - pi.received_quantity
        if (line.quantity > rem) throw new Error(`Jumlah diterima melebihi sisa pengadaan (${rem} tersisa)`)
        pi.received_quantity += line.quantity
      }
      const k = `${line.variantId}:${line.condition}`
      const cur = netMap.get(k) || { variantId: line.variantId, condition: line.condition, delta: 0, notes: line.notes ?? null }
      cur.delta += Number(line.quantity)
      cur.notes = line.notes ?? cur.notes
      netMap.set(k, cur)

      items.push({
        id: crypto.randomUUID(),
        procurement_item_id: line.procurementItemId ?? null,
        variant_id: line.variantId,
        quantity: line.quantity,
        condition: line.condition,
        serial_number: line.serialNumber ?? null,
        receiver_name: line.receiverName,
        receipt_proof_key: line.receiptProofKey ?? null,
        notes: line.notes ?? null,
      })
    }

    for (const entry of netMap.values()) {
      if (entry.delta !== 0) {
        this.applyMovement(
          state,
          entry.variantId,
          entry.condition,
          entry.delta,
          'receipt',
          'purchase',
          id,
          entry.notes || (nextProc ? `Revisi penerimaan ${nextProc.procurement_no}` : 'Revisi barang masuk'),
          this.toOccurredAt(input.receivedDate),
        )
      }
    }

    if (nextProc) {
      const totalOrd = nextProc.items.reduce((s, i) => s + i.ordered_quantity, 0)
      const totalRec = nextProc.items.reduce((s, i) => s + i.received_quantity, 0)
      nextProc.status = totalRec >= totalOrd && totalOrd > 0 ? 'completed' : totalRec > 0 ? 'partial' : 'ordered'
    }

    pur.procurement_id = nextProc?.id ?? null
    pur.received_date = new Date(input.receivedDate).toISOString().slice(0, 10)
    pur.supplier_id = input.supplierId || nextProc?.supplier_id || pur.supplier_id
    pur.reason = input.reason || nextProc?.reason || pur.reason
    pur.billing_proof_key = input.billingProofKey ?? pur.billing_proof_key
    pur.items = items

    await this.save(state)
    return id
  }

  async listIssuances({ search, employeeId }: { search?: string; employeeId?: string }) {
    const state = await this.load()
    let rows = [...state.issuances]
    if (employeeId) rows = rows.filter((i) => i.employee_id === employeeId)
    if (search) {
      const q = search.toLowerCase()
      rows = rows.filter((i) => {
        const emp = state.employees.find((e) => e.id === i.employee_id)
        return i.transaction_no.toLowerCase().includes(q) || i.officer_name.toLowerCase().includes(q) || (emp?.name || '').toLowerCase().includes(q)
      })
    }
    return rows
      .sort((a, b) => new Date(b.issued_at).getTime() - new Date(a.issued_at).getTime())
      .map((iss) => {
        const emp = state.employees.find((e) => e.id === iss.employee_id)
        const dept = emp ? state.departments.find((d) => d.id === emp.department_id) : null
        return {
          ...iss,
          employees: emp ? { ...emp, departments: dept ? { name: dept.name } : null } : null,
          issuance_items: iss.items.map((it) => ({ ...it, item_variants: this.enrichVariant(state, it.variant_id) })),
        }
      })
  }

  async listOpenIssuanceItemsByEmployee(employeeId: string) {
    const state = await this.load()
    const results: Record<string, unknown>[] = []
    for (const iss of state.issuances) {
      if (iss.employee_id !== employeeId) continue
      for (const it of iss.items) {
        const remaining = it.quantity - it.returned_quantity - it.resolved_lost_quantity
        if (remaining > 0) {
          results.push({
            ...it,
            remaining_quantity: remaining,
            issuances: { id: iss.id, transaction_no: iss.transaction_no, issued_at: iss.issued_at, employee_id: iss.employee_id },
            item_variants: this.enrichVariant(state, it.variant_id),
          })
        }
      }
    }
    return results
  }

  private allocateAndDeductIssuanceLines(
    state: LocalState,
    issuanceId: string,
    occurredAt: string,
    lines: IssuanceInput['items'],
  ): LocalState['issuances'][number]['items'] {
    const items: LocalState['issuances'][number]['items'] = []
    const getBal = (variantId: string, cond: StockCondition) =>
      Number(state.stock_balances.find((b) => b.variant_id === variantId && b.condition === cond)?.quantity ?? 0)

    const pushLine = (variantId: string, condition: 'new' | 'used_good', quantity: number, purpose: string, notes: string | null) => {
      this.applyMovement(state, variantId, condition, -quantity, 'issuance', 'issuance', issuanceId, purpose, occurredAt)
      items.push({
        id: crypto.randomUUID(),
        issuance_id: issuanceId,
        variant_id: variantId,
        condition,
        quantity,
        returned_quantity: 0,
        resolved_lost_quantity: 0,
        purpose,
        notes,
      })
    }

    for (const line of lines) {
      if (line.condition === 'new' || line.condition === 'used_good') {
        pushLine(line.variantId, line.condition, line.quantity, line.purpose, line.notes ?? null)
        continue
      }
      const stockNew = getBal(line.variantId, 'new')
      const stockUsed = getBal(line.variantId, 'used_good')
      const totalAvail = stockNew + stockUsed
      if (line.quantity > totalAvail) {
        throw new Error(`Stok tersedia tidak mencukupi (tersedia ${totalAvail})`)
      }
      const takeNew = Math.min(stockNew, line.quantity)
      const takeUsed = line.quantity - takeNew
      if (takeNew > 0) pushLine(line.variantId, 'new', takeNew, line.purpose, line.notes ?? null)
      if (takeUsed > 0) pushLine(line.variantId, 'used_good', takeUsed, line.purpose, line.notes ?? null)
    }
    return items
  }

  async createIssuance(input: IssuanceInput, idempotencyKey: string): Promise<string> {
    const state = await this.load()
    if (state.idempotency[idempotencyKey]) return state.idempotency[idempotencyKey]!

    state.seq.issuance += 1
    const issuanceId = crypto.randomUUID()
    const issuedAt = new Date(input.issuedAt).toISOString().slice(0, 10)
    const items = this.allocateAndDeductIssuanceLines(state, issuanceId, this.toOccurredAt(input.issuedAt), input.items)

    state.issuances.push({
      id: issuanceId,
      transaction_no: this.nextDocNo('BK', state.seq.issuance),
      issued_at: issuedAt,
      employee_id: input.employeeId,
      officer_name: input.officerName,
      ba_key: input.baKey ?? null,
      handover_proof_key: input.handoverProofKey ?? null,
      notes: input.notes ?? null,
      created_at: new Date().toISOString(),
      items,
    })

    state.idempotency[idempotencyKey] = issuanceId
    await this.save(state)
    return issuanceId
  }

  async updateIssuance(id: string, input: IssuanceInput): Promise<string> {
    const state = await this.load()
    const iss = state.issuances.find((i) => i.id === id)
    if (!iss) throw new Error('Transaksi barang keluar tidak ditemukan')
    const issItemMap = new Map(iss.items.map((it) => [it.id, it]))
    for (const ret of [...state.returns]) {
      const removed = ret.items.filter((ri) => issItemMap.has(ri.issuance_item_id))
      if (!removed.length) continue
      for (const ri of removed) {
        const parent = issItemMap.get(ri.issuance_item_id)!
        if (ri.result !== 'lost') {
          const targetCond: StockCondition | null =
            ri.result === 'used_good' ? 'used_good'
              : ri.result === 'maintenance' ? 'quarantine'
                : ri.result === 'damaged' && ri.reusable ? 'used_good'
                  : null
          if (targetCond) {
            const bal = state.stock_balances.find((b) => b.variant_id === parent.variant_id && b.condition === targetCond)
            const cur = Number(bal?.quantity ?? 0)
            const delta = -Math.min(cur, ri.quantity)
            if (delta !== 0) this.applyMovement(state, parent.variant_id, targetCond, delta, 'return', 'return', ret.id, `Revisi barang keluar ${iss.transaction_no}`, new Date().toISOString())
          }
        }
      }
      ret.items = ret.items.filter((ri) => !issItemMap.has(ri.issuance_item_id))
    }
    state.returns = state.returns.filter((r) => r.items.length > 0)

    for (const old of iss.items) {
      this.applyMovement(state, old.variant_id, old.condition, old.quantity, 'issuance', 'issuance', id, 'Revisi barang keluar (koreksi)', new Date().toISOString())
    }

    const items = this.allocateAndDeductIssuanceLines(state, id, this.toOccurredAt(input.issuedAt), input.items)

    iss.issued_at = new Date(input.issuedAt).toISOString().slice(0, 10)
    iss.employee_id = input.employeeId
    iss.officer_name = input.officerName
    iss.handover_proof_key = input.handoverProofKey ?? iss.handover_proof_key
    iss.notes = input.notes ?? null
    iss.items = items

    await this.save(state)
    return id
  }

  async listReturns({ result, search }: { result?: string; search?: string }) {
    const state = await this.load()
    let rows = [...state.returns]
    if (result && result !== 'all') {
      rows = rows.filter((r) => r.items.some((it) => it.result === result))
    }
    if (search) {
      const q = search.toLowerCase()
      rows = rows.filter((r) => {
        const emp = state.employees.find((e) => e.id === r.employee_id)
        return r.transaction_no.toLowerCase().includes(q) || r.inspector_name.toLowerCase().includes(q) || (emp?.name || '').toLowerCase().includes(q)
      })
    }
    const allIssuanceItems = new Map<string, LocalState['issuances'][number]['items'][number]>()
    for (const iss of state.issuances) {
      for (const it of iss.items) allIssuanceItems.set(it.id, it)
    }

    return rows
      .sort((a, b) => new Date(b.returned_at).getTime() - new Date(a.returned_at).getTime())
      .map((ret) => {
        const emp = state.employees.find((e) => e.id === ret.employee_id)
        const dept = emp ? state.departments.find((d) => d.id === emp.department_id) : null
        return {
          ...ret,
          employees: emp ? { ...emp, departments: dept ? { name: dept.name } : null } : null,
          return_items: ret.items.map((it) => {
            const issItem = allIssuanceItems.get(it.issuance_item_id)
            return {
              ...it,
              issuance_items: issItem ? { condition: issItem.condition, item_variants: this.enrichVariant(state, issItem.variant_id) } : null,
            }
          }),
        }
      })
  }

  async createReturn(input: ReturnInput, idempotencyKey: string): Promise<string> {
    const state = await this.load()
    if (state.idempotency[idempotencyKey]) return state.idempotency[idempotencyKey]!

    state.seq.return += 1
    const returnId = crypto.randomUUID()
    const returnedAt = new Date(input.returnedAt).toISOString().slice(0, 10)
    const items: LocalState['returns'][number]['items'] = []

    for (const line of input.items) {
      let foundIss: LocalState['issuances'][number] | undefined
      let foundLine: LocalState['issuances'][number]['items'][number] | undefined
      for (const iss of state.issuances) {
        const match = iss.items.find((x) => x.id === line.issuanceItemId)
        if (match) {
          foundIss = iss
          foundLine = match
          break
        }
      }
      if (!foundIss || !foundLine) throw new Error('Detail pengeluaran tidak ditemukan')
      if (foundIss.employee_id !== input.employeeId) throw new Error('Pengeluaran tidak dimiliki karyawan yang dipilih')

      const remaining = foundLine.quantity - foundLine.returned_quantity - foundLine.resolved_lost_quantity
      if (line.quantity > remaining) throw new Error(`Jumlah pengembalian melebihi sisa tanggungan ${remaining}`)
      if (line.inspectionResult === 'lost' && !line.reason?.trim()) {
        throw new Error('Alasan wajib diisi untuk penyelesaian kehilangan')
      }

      if (line.inspectionResult === 'lost') {
        foundLine.resolved_lost_quantity += line.quantity
      } else {
        foundLine.returned_quantity += line.quantity
        const targetCond: StockCondition | null =
          line.inspectionResult === 'used_good' ? 'used_good'
            : line.inspectionResult === 'maintenance' ? 'quarantine'
              : line.inspectionResult === 'damaged' && line.reusable ? 'used_good'
                : null
        if (targetCond) {
          this.applyMovement(
            state,
            foundLine.variant_id,
            targetCond,
            line.quantity,
            'return',
            'return',
            returnId,
            line.reason || (line.inspectionResult === 'damaged' ? 'Pengembalian APD rusak (masih layak pakai ulang)' : 'Pengembalian APD'),
            this.toOccurredAt(input.returnedAt),
          )
        }
      }

      items.push({
        id: crypto.randomUUID(),
        issuance_item_id: line.issuanceItemId,
        quantity: line.quantity,
        result: line.inspectionResult,
        reusable: line.inspectionResult === 'damaged' ? Boolean(line.reusable) : undefined,
        reason: line.reason ?? null,
        notes: line.notes ?? null,
      })
    }

    state.returns.push({
      id: returnId,
      transaction_no: this.nextDocNo('PG', state.seq.return),
      returned_at: returnedAt,
      employee_id: input.employeeId,
      inspector_name: input.inspectorName,
      proof_key: input.proofKey ?? null,
      created_at: new Date().toISOString(),
      items,
    })

    state.idempotency[idempotencyKey] = returnId
    await this.save(state)
    return returnId
  }

  async updateReturn(id: string, input: ReturnInput): Promise<string> {
    const state = await this.load()
    const ret = state.returns.find((r) => r.id === id)
    if (!ret) throw new Error('Transaksi pengembalian tidak ditemukan')

    const findIssLine = (issItemId: string) => {
      for (const iss of state.issuances) {
        const match = iss.items.find((x) => x.id === issItemId)
        if (match) return { iss, line: match }
      }
      return null
    }

    for (const old of ret.items) {
      const found = findIssLine(old.issuance_item_id)
      if (!found) continue
      if (old.result === 'lost') {
        found.line.resolved_lost_quantity = Math.max(0, found.line.resolved_lost_quantity - old.quantity)
      } else {
        found.line.returned_quantity = Math.max(0, found.line.returned_quantity - old.quantity)
        const targetCond: StockCondition | null =
          old.result === 'used_good' ? 'used_good'
            : old.result === 'maintenance' ? 'quarantine'
              : old.result === 'damaged' && old.reusable === true ? 'used_good'
                : old.result === 'damaged' && old.reusable === undefined ? 'damaged'
                  : null
        if (targetCond) {
          this.applyMovement(state, found.line.variant_id, targetCond, -old.quantity, 'return', 'return', id, 'Revisi pengembalian (koreksi)', new Date().toISOString())
        }
      }
    }

    const items: LocalState['returns'][number]['items'] = []
    for (const line of input.items) {
      const found = findIssLine(line.issuanceItemId)
      if (!found) throw new Error('Detail pengeluaran tidak ditemukan')
      if (found.iss.employee_id !== input.employeeId) throw new Error('Pengeluaran tidak dimiliki karyawan yang dipilih')

      const remaining = found.line.quantity - found.line.returned_quantity - found.line.resolved_lost_quantity
      if (line.quantity > remaining) throw new Error(`Jumlah pengembalian melebihi sisa tanggungan ${remaining}`)
      if (line.inspectionResult === 'lost' && !line.reason?.trim()) throw new Error('Alasan wajib diisi untuk kehilangan')

      if (line.inspectionResult === 'lost') {
        found.line.resolved_lost_quantity += line.quantity
      } else {
        found.line.returned_quantity += line.quantity
        const targetCond: StockCondition | null =
          line.inspectionResult === 'used_good' ? 'used_good'
            : line.inspectionResult === 'maintenance' ? 'quarantine'
              : line.inspectionResult === 'damaged' && line.reusable ? 'used_good'
                : null
        if (targetCond) {
          this.applyMovement(state, found.line.variant_id, targetCond, line.quantity, 'return', 'return', id, line.reason || (line.inspectionResult === 'damaged' ? 'Revisi pengembalian APD rusak (masih layak pakai ulang)' : 'Revisi pengembalian APD'), this.toOccurredAt(input.returnedAt))
        }
      }

      items.push({
        id: crypto.randomUUID(),
        issuance_item_id: line.issuanceItemId,
        quantity: line.quantity,
        result: line.inspectionResult,
        reusable: line.inspectionResult === 'damaged' ? Boolean(line.reusable) : undefined,
        reason: line.reason ?? null,
        notes: line.notes ?? null,
      })
    }

    ret.returned_at = new Date(input.returnedAt).toISOString().slice(0, 10)
    ret.employee_id = input.employeeId
    ret.inspector_name = input.inspectorName
    ret.proof_key = input.proofKey ?? ret.proof_key
    ret.items = items

    await this.save(state)
    return id
  }

  async listStocktakes({ status }: { status?: string }) {
    const state = await this.load()
    let rows = [...state.stocktakes]
    if (status && status !== 'all') rows = rows.filter((s) => s.status === status)
    return rows
      .sort((a, b) => new Date(b.created_at).getTime() - new Date(a.created_at).getTime())
      .map((st) => ({
        ...st,
        stocktake_items: st.items.map((it) => ({ ...it, item_variants: this.enrichVariant(state, it.variant_id) })),
      }))
  }

  async createStocktake(input: StocktakeCreateInput): Promise<string> {
    const state = await this.load()
    state.seq.stocktake += 1
    const id = crypto.randomUUID()
    const refAt = input.referenceAt ? this.toOccurredAt(input.referenceAt) : new Date().toISOString()

    const items = input.items.map((line) => {
      const bal = state.stock_balances.find((b) => b.variant_id === line.variantId && b.condition === line.condition)
      const sysQty = Number(bal?.quantity ?? 0)
      return {
        id: crypto.randomUUID(),
        variant_id: line.variantId,
        condition: line.condition,
        system_quantity: sysQty,
        physical_quantity: line.physicalQuantity,
        reason: line.reason ?? null,
        adjustment_quantity: line.physicalQuantity - sysQty,
      }
    })

    const st = {
      id,
      stocktake_no: this.nextDocNo('SO', state.seq.stocktake),
      reference_at: refAt,
      officer_name: input.officerName,
      status: 'pending_review' as const,
      submitted_at: new Date().toISOString(),
      finalized_at: null,
      created_at: new Date().toISOString(),
      items,
    }
    state.stocktakes.push(st)
    await this.save(state)

    if (input.finalizeNow) {
      return this.finalizeStocktake(id)
    }
    return id
  }

  async updateStocktake(id: string, input: StocktakeCreateInput): Promise<string> {
    const state = await this.load()
    const st = state.stocktakes.find((s) => s.id === id)
    if (!st) throw new Error('Stok opname tidak ditemukan')
    const wasCompleted = st.status === 'completed'

    if (wasCompleted) {
      for (const old of st.items) {
        const adj = Number(old.adjustment_quantity || 0)
        if (adj !== 0) {
          this.applyMovement(state, old.variant_id, old.condition, -adj, 'stocktake_adjustment', 'stocktake', st.id, `Revisi ${st.stocktake_no} (koreksi)`, new Date().toISOString())
        }
      }
    }

    st.officer_name = input.officerName
    if (input.referenceAt) st.reference_at = this.toOccurredAt(input.referenceAt)
    st.items = input.items.map((line) => {
      const bal = state.stock_balances.find((b) => b.variant_id === line.variantId && b.condition === line.condition)
      const sysQty = Number(bal?.quantity ?? 0)
      const adj = line.physicalQuantity - sysQty
      if (wasCompleted && adj !== 0) {
        this.applyMovement(state, line.variantId, line.condition, adj, 'stocktake_adjustment', 'stocktake', st.id, line.reason || `Revisi ${st.stocktake_no}`, new Date().toISOString())
      }
      return {
        id: crypto.randomUUID(),
        variant_id: line.variantId,
        condition: line.condition,
        system_quantity: sysQty,
        physical_quantity: line.physicalQuantity,
        reason: line.reason ?? null,
        adjustment_quantity: adj,
      }
    })

    await this.save(state)
    if (!wasCompleted && input.finalizeNow) {
      return this.finalizeStocktake(id)
    }
    return id
  }

  async deleteStocktake(id: string): Promise<void> {
    const state = await this.load()
    const idx = state.stocktakes.findIndex((s) => s.id === id)
    if (idx === -1) throw new Error('Stok opname tidak ditemukan')
    const st = state.stocktakes[idx]!
    if (st.status === 'completed') {
      for (const old of st.items) {
        const adj = Number(old.adjustment_quantity || 0)
        if (adj !== 0) {
          this.applyMovement(state, old.variant_id, old.condition, -adj, 'stocktake_adjustment', 'stocktake', st.id, `Hapus ${st.stocktake_no} (pembalikan stok)`, new Date().toISOString())
        }
      }
    }
    state.stocktakes.splice(idx, 1)
    await this.save(state)
  }

  async finalizeStocktake(stocktakeId: string): Promise<string> {
    const state = await this.load()
    const st = state.stocktakes.find((s) => s.id === stocktakeId)
    if (!st) throw new Error('Stok opname tidak ditemukan')
    if (st.status !== 'pending_review') throw new Error('Stok opname harus berstatus Menunggu Pemeriksaan')

    for (const line of st.items) {
      const bal = state.stock_balances.find((b) => b.variant_id === line.variant_id && b.condition === line.condition)
      const currentQty = Number(bal?.quantity ?? 0)
      const adjustment = line.physical_quantity - currentQty
      if (adjustment !== 0) {
        this.applyMovement(
          state,
          line.variant_id,
          line.condition,
          adjustment,
          'stocktake_adjustment',
          'stocktake',
          st.id,
          line.reason || `Penyesuaian ${st.stocktake_no}`,
          new Date().toISOString(),
        )
      }
      line.system_quantity = currentQty
      line.adjustment_quantity = adjustment
    }

    st.status = 'completed'
    st.finalized_at = new Date().toISOString()
    await this.save(state)
    return st.id
  }

  async createReimbursement(input: ReimbursementInput): Promise<string> {
    const state = await this.load()
    const purchase = state.purchases.find((p) => p.id === input.purchaseId)
    if (!purchase) throw new Error('Pembelian tidak ditemukan')
    purchase.reimbursement_status = 'paid'
    await this.save(state)
    return crypto.randomUUID()
  }

  async getEmployeeLiabilities() {
    const state = await this.load()
    const rows: Record<string, unknown>[] = []
    for (const iss of state.issuances) {
      const emp = state.employees.find((e) => e.id === iss.employee_id)
      const dept = emp ? state.departments.find((d) => d.id === emp.department_id) : null
      for (const it of iss.items) {
        const remaining = it.quantity - it.returned_quantity - it.resolved_lost_quantity
        if (remaining > 0) {
          rows.push({
            ...it,
            issuances: {
              transaction_no: iss.transaction_no,
              issued_at: iss.issued_at,
              employees: emp ? { ...emp, departments: dept ? { name: dept.name } : null } : null,
            },
            item_variants: this.enrichVariant(state, it.variant_id),
          })
        }
      }
    }
    return rows
  }
}
