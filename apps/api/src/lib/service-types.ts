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

export interface InventoryRow {
  variant_id: string
  item_id: string
  code: string
  name: string
  category_id?: string
  category_name: string
  specification: string | null
  size: string
  unit: string
  minimum_stock: number
  return_required: boolean
  photo_key: string | null
  stock_new: number
  stock_used_good: number
  stock_quarantine: number
  stock_damaged: number
  total_available: number
  stock_status: 'safe' | 'low' | 'out'
}

export interface InventoryService {
  getDashboard(month: number, year: number, period?: 'all' | 'year' | 'month'): Promise<Record<string, unknown>>
  getMasterSummary(): Promise<{
    categories: Record<string, unknown>[]
    departments: Record<string, unknown>[]
    items: Record<string, unknown>[]
    variants: Record<string, unknown>[]
    employees: Record<string, unknown>[]
    suppliers: Record<string, unknown>[]
    funders: Record<string, unknown>[]
    officers: Record<string, unknown>[]
  }>
  saveCategory(id: string | null, input: CategoryInput): Promise<Record<string, unknown>>
  deleteCategory(id: string): Promise<void>
  saveDepartment(id: string | null, input: DepartmentInput): Promise<Record<string, unknown>>
  deleteDepartment(id: string): Promise<void>
  saveSupplier(id: string | null, input: SupplierInput): Promise<Record<string, unknown>>
  deleteSupplier(id: string): Promise<void>
  saveFunder(id: string | null, input: FunderInput): Promise<Record<string, unknown>>
  deleteFunder(id: string): Promise<void>
  saveOfficer(id: string | null, input: OfficerInput): Promise<Record<string, unknown>>
  deleteOfficer(id: string): Promise<void>
  saveEmployee(id: string | null, input: EmployeeInput): Promise<Record<string, unknown>>
  deleteEmployee(id: string): Promise<void>
  saveItem(id: string | null, input: ItemInput): Promise<Record<string, unknown>>
  deleteItem(id: string): Promise<void>

  listInventory(params: {
    page: number
    limit: number
    search?: string
    status?: string
    categoryId?: string
  }): Promise<{ data: InventoryRow[]; pagination: { page: number; limit: number; total: number; totalPages: number } }>

  listMovements(params: { variantId?: string; limit?: number }): Promise<Record<string, unknown>[]>
  listOpeningStocks(): Promise<Record<string, unknown>[]>
  createOpeningStock(input: OpeningStockInput, idempotencyKey: string): Promise<string>
  updateOpeningStock(id: string, input: OpeningStockInput): Promise<string>
  deleteOpeningStock(id: string): Promise<void>
  transferCondition(input: ConditionTransferInput): Promise<string>

  listProcurements(params: {
    status?: string
    paymentStatus?: string
    search?: string
    variantId?: string
    onlyPendingReceipt?: boolean
  }): Promise<Record<string, unknown>[]>
  getProcurement(id: string): Promise<Record<string, unknown>>
  createProcurement(input: ProcurementInput, idempotencyKey: string): Promise<string>
  updateProcurement(id: string, input: ProcurementInput): Promise<string>
  deleteProcurement(id: string): Promise<void>
  updateProcurementStatus(id: string, status: string): Promise<void>
  createProcurementPayment(input: ProcurementPaymentInput): Promise<string>
  updateProcurementPayment(id: string, input: ProcurementPaymentInput): Promise<string>
  deleteProcurementPayment(id: string): Promise<void>
  listPayments(): Promise<Record<string, unknown>[]>

  listPurchases(params: { fundingSource?: string; search?: string }): Promise<Record<string, unknown>[]>
  createPurchaseReceipt(input: PurchaseInput, idempotencyKey: string): Promise<string>
  updatePurchaseReceipt(id: string, input: PurchaseInput): Promise<string>
  deletePurchaseReceipt(id: string): Promise<void>

  listIssuances(params: { search?: string; employeeId?: string }): Promise<Record<string, unknown>[]>
  listOpenIssuanceItemsByEmployee(employeeId: string): Promise<Record<string, unknown>[]>
  createIssuance(input: IssuanceInput, idempotencyKey: string): Promise<string>
  updateIssuance(id: string, input: IssuanceInput): Promise<string>
  deleteIssuance(id: string): Promise<void>

  listReturns(params: { result?: string; search?: string }): Promise<Record<string, unknown>[]>
  createReturn(input: ReturnInput, idempotencyKey: string): Promise<string>
  updateReturn(id: string, input: ReturnInput): Promise<string>
  deleteReturn(id: string): Promise<void>

  listStocktakes(params: { status?: string }): Promise<Record<string, unknown>[]>
  createStocktake(input: StocktakeCreateInput): Promise<string>
  updateStocktake(id: string, input: StocktakeCreateInput): Promise<string>
  deleteStocktake(id: string): Promise<void>
  finalizeStocktake(stocktakeId: string): Promise<string>

  createReimbursement(input: ReimbursementInput): Promise<string>
  getEmployeeLiabilities(): Promise<Record<string, unknown>[]>
}

export type StockConditionMap = Record<StockCondition, number>
