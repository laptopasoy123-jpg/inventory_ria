import { z } from 'zod'

export const stockConditions = ['new', 'used_good', 'quarantine', 'damaged'] as const
export const availableConditions = ['new', 'used_good'] as const
export const roles = ['officer', 'inspector', 'admin'] as const
export const units = ['pcs', 'pasang', 'box', 'set', 'unit', 'roll'] as const
export const procurementStatuses = ['draft', 'ordered', 'partial', 'completed', 'cancelled'] as const
export const paymentTypes = ['dp', 'installment', 'full', 'reimbursement'] as const

export type StockCondition = (typeof stockConditions)[number]
export type UserRole = (typeof roles)[number]
export type ProcurementStatus = (typeof procurementStatuses)[number]

export const paginationSchema = z.object({
  page: z.coerce.number().int().min(1).default(1),
  limit: z.coerce.number().int().min(1).max(200).default(20),
  search: z.string().trim().max(100).optional(),
})

export const categorySchema = z.object({
  code: z.string().trim().min(1).max(30),
  name: z.string().trim().min(2).max(120),
})

export const departmentSchema = z.object({
  code: z.string().trim().min(1).max(30),
  name: z.string().trim().min(2).max(120),
  active: z.boolean().default(true),
})

export const supplierSchema = z.object({
  code: z.string().trim().min(1).max(30),
  name: z.string().trim().min(2).max(160),
  vendorType: z.enum(['supplier', 'online_shop']).default('supplier'),
  contactName: z.string().trim().max(120).nullable().optional(),
  phone: z.string().trim().max(40).nullable().optional(),
  address: z.string().trim().max(300).nullable().optional(),
  active: z.boolean().default(true),
})

export const funderSchema = z.object({
  name: z.string().trim().min(2).max(160),
  phone: z.string().trim().max(40).nullable().optional(),
  notes: z.string().trim().max(300).nullable().optional(),
  active: z.boolean().default(true),
})

export const officerSchema = z.object({
  name: z.string().trim().min(2).max(160),
  roleLabel: z.string().trim().min(2).max(120).default('Petugas Gudang'),
  active: z.boolean().default(true),
})

export const itemSchema = z.object({
  code: z.string().trim().min(2).max(40),
  name: z.string().trim().min(2).max(160),
  categoryId: z.string().uuid().nullable().optional(),
  specification: z.string().trim().max(500).nullable().optional(),
  unit: z.string().trim().min(1).max(30),
  minimumStock: z.coerce.number().min(0),
  photoKey: z.string().trim().max(500).nullable().optional(),
  returnRequired: z.boolean().default(true),
  active: z.boolean().default(true),
  sizes: z.array(z.string().trim().min(1).max(30)).min(1).default(['-']),
})

export const employeeSchema = z.object({
  nik: z.string().trim().min(2).max(40),
  name: z.string().trim().min(2).max(160),
  position: z.string().trim().min(2).max(120),
  departmentId: z.string().uuid(),
  contractStatus: z.enum(['permanent', 'contract', 'intern', 'inactive']),
})

export const openingStockItemSchema = z.object({
  variantId: z.string().uuid(),
  condition: z.enum(stockConditions),
  quantity: z.coerce.number().positive(),
  notes: z.string().trim().max(500).nullable().optional(),
})

export const openingStockSchema = z.object({
  recordedAt: z.coerce.date(),
  officerName: z.string().trim().min(2).max(160),
  notes: z.string().trim().max(1000).nullable().optional(),
  items: z.array(openingStockItemSchema).min(1),
})

export const procurementItemSchema = z.object({
  id: z.string().uuid().optional(),
  variantId: z.string().uuid(),
  orderedQuantity: z.coerce.number().positive(),
  unitPrice: z.coerce.number().min(0).default(0),
  notes: z.string().trim().max(500).nullable().optional(),
})

export const procurementSchema = z.object({
  procurementDate: z.coerce.date(),
  expectedDate: z.coerce.date().nullable().optional(),
  prNumber: z.string().trim().max(80).nullable().optional(),
  poNumber: z.string().trim().max(80).nullable().optional(),
  departmentId: z.string().uuid().nullable().optional(),
  supplierId: z.string().uuid(),
  reason: z.string().trim().min(3).max(1000),
  fundingSource: z.enum(['company', 'advanced']),
  paymentMethod: z.enum(['cash', 'transfer']),
  funderId: z.string().uuid().nullable().optional(),
  totalAmount: z.coerce.number().min(0).optional(),
  documentKey: z.string().max(500).nullable().optional(),
  notes: z.string().trim().max(1000).nullable().optional(),
  items: z.array(procurementItemSchema).min(1),
}).superRefine((value, ctx) => {
  if (value.fundingSource === 'advanced' && !value.funderId) {
    ctx.addIssue({ code: z.ZodIssueCode.custom, path: ['funderId'], message: 'Pihak penalang wajib dipilih' })
  }
})

export const receiptItemSchema = z.object({
  procurementItemId: z.string().uuid().nullable().optional(),
  variantId: z.string().uuid(),
  quantity: z.coerce.number().positive(),
  condition: z.enum(stockConditions),
  serialNumber: z.string().trim().max(160).nullable().optional(),
  receiverName: z.string().trim().min(2).max(160),
  receiptProofKey: z.string().trim().max(500).nullable().optional(),
  notes: z.string().trim().max(1000).nullable().optional(),
})

export const purchaseSchema = z.object({
  procurementId: z.string().uuid().nullable().optional(),
  purchaseDate: z.coerce.date().optional(),
  receivedDate: z.coerce.date(),
  prNumber: z.string().trim().max(80).nullable().optional(),
  requestNumber: z.string().trim().max(80).nullable().optional(),
  poNumber: z.string().trim().max(80).nullable().optional(),
  deliveryNoteNumber: z.string().trim().max(80).nullable().optional(),
  invoiceNumber: z.string().trim().max(80).nullable().optional(),
  reason: z.string().trim().min(2).max(1000),
  supplierId: z.string().uuid(),
  billingProofKey: z.string().max(500).nullable().optional(),
  paymentProofKey: z.string().max(500).nullable().optional(),
  totalPaid: z.coerce.number().min(0).default(0),
  fundingSource: z.enum(['company', 'advanced']).default('company'),
  paymentMethod: z.enum(['cash', 'transfer']).default('transfer'),
  funderId: z.string().uuid().nullable().optional(),
  items: z.array(receiptItemSchema).min(1),
}).superRefine((value, ctx) => {
  if (value.fundingSource === 'advanced' && !value.funderId) {
    ctx.addIssue({ code: z.ZodIssueCode.custom, path: ['funderId'], message: 'Pihak penalang wajib dipilih' })
  }
})

export const procurementPaymentSchema = z.object({
  procurementId: z.string().uuid(),
  paidAt: z.coerce.date(),
  amount: z.coerce.number().positive(),
  paymentMethod: z.enum(['cash', 'transfer']),
  paymentType: z.enum(paymentTypes).default('full'),
  referenceNo: z.string().trim().max(120).nullable().optional(),
  proofKey: z.string().max(500).nullable().optional(),
  notes: z.string().trim().max(1000).nullable().optional(),
})

export const issuanceItemSchema = z.object({
  variantId: z.string().uuid(),
  condition: z.enum(['auto', 'new', 'used_good']).optional().default('auto'),
  quantity: z.coerce.number().positive(),
  purpose: z.string().trim().min(2).max(500),
  notes: z.string().trim().max(1000).nullable().optional(),
})

export const issuanceSchema = z.object({
  issuedAt: z.coerce.date(),
  employeeId: z.string().uuid(),
  officerName: z.string().trim().min(2).max(160),
  handoverProofKey: z.string().max(500).nullable().optional(),
  baKey: z.string().max(500).nullable().optional(),
  notes: z.string().trim().max(1000).nullable().optional(),
  items: z.array(issuanceItemSchema).min(1),
})

export const returnItemSchema = z.object({
  issuanceItemId: z.string().uuid(),
  quantity: z.coerce.number().positive(),
  inspectionResult: z.enum(['used_good', 'maintenance', 'damaged', 'lost']),
  reusable: z.boolean().optional().default(false),
  reason: z.string().trim().max(500).nullable().optional(),
  notes: z.string().trim().max(1000).nullable().optional(),
})

export const returnSchema = z.object({
  returnedAt: z.coerce.date(),
  employeeId: z.string().uuid(),
  inspectorName: z.string().trim().min(2).max(160),
  proofKey: z.string().max(500).nullable().optional(),
  items: z.array(returnItemSchema).min(1),
})

export const reimbursementSchema = z.object({
  purchaseId: z.string().uuid(),
  reimbursedAt: z.coerce.date(),
  amount: z.coerce.number().positive(),
  proofKey: z.string().max(500).nullable().optional(),
  notes: z.string().trim().max(1000).nullable().optional(),
})

export const conditionTransferSchema = z.object({
  variantId: z.string().uuid(),
  fromCondition: z.enum(stockConditions),
  toCondition: z.enum(stockConditions),
  quantity: z.coerce.number().positive(),
  notes: z.string().trim().max(500).nullable().optional(),
})

export const stocktakeItemInputSchema = z.object({
  variantId: z.string().uuid(),
  condition: z.enum(stockConditions),
  physicalQuantity: z.coerce.number().min(0),
  reason: z.string().trim().max(500).nullable().optional(),
})

export const stocktakeCreateSchema = z.object({
  officerName: z.string().trim().min(2).max(160),
  referenceAt: z.coerce.date().optional(),
  finalizeNow: z.boolean().default(false),
  items: z.array(stocktakeItemInputSchema).min(1),
})

export const stocktakeFinalizeSchema = z.object({ stocktakeId: z.string().uuid() })

export const companySettingsSchema = z.object({
  name: z.string().trim().min(2).max(160),
  tagline: z.string().trim().max(200).nullable().optional(),
  logoKey: z.string().max(500).nullable().optional(),
})
export type CompanySettingsInput = z.infer<typeof companySettingsSchema>

export type CategoryInput = z.infer<typeof categorySchema>
export type DepartmentInput = z.infer<typeof departmentSchema>
export type SupplierInput = z.infer<typeof supplierSchema>
export type FunderInput = z.infer<typeof funderSchema>
export type OfficerInput = z.infer<typeof officerSchema>
export type ItemInput = z.infer<typeof itemSchema>
export type EmployeeInput = z.infer<typeof employeeSchema>
export type OpeningStockInput = z.infer<typeof openingStockSchema>
export type ProcurementInput = z.infer<typeof procurementSchema>
export type PurchaseInput = z.infer<typeof purchaseSchema>
export type ProcurementPaymentInput = z.infer<typeof procurementPaymentSchema>
export type IssuanceInput = z.infer<typeof issuanceSchema>
export type ReturnInput = z.infer<typeof returnSchema>
export type ReimbursementInput = z.infer<typeof reimbursementSchema>
export type ConditionTransferInput = z.infer<typeof conditionTransferSchema>
export type StocktakeCreateInput = z.infer<typeof stocktakeCreateSchema>

export interface ApiResponse<T> {
  data: T
  message?: string
}

export interface PaginatedResponse<T> {
  data: T[]
  pagination: { page: number; limit: number; total: number; totalPages: number }
}
