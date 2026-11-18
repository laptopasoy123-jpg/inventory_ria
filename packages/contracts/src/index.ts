import { z } from 'zod'

export const stockConditions = ['new', 'used_good', 'quarantine', 'damaged'] as const
export const availableConditions = ['new', 'used_good'] as const
export const roles = ['officer', 'inspector', 'admin'] as const
export const units = ['pcs', 'pasang', 'box', 'set', 'unit', 'roll'] as const

export type StockCondition = (typeof stockConditions)[number]
export type UserRole = (typeof roles)[number]

export const paginationSchema = z.object({
  page: z.coerce.number().int().min(1).default(1),
  limit: z.coerce.number().int().min(1).max(100).default(20),
  search: z.string().trim().max(100).optional(),
})

export const itemSchema = z.object({
  code: z.string().trim().min(2).max(40),
  name: z.string().trim().min(2).max(160),
  categoryId: z.string().uuid(),
  specification: z.string().trim().max(500).nullable().optional(),
  unit: z.string().trim().min(1).max(30),
  minimumStock: z.coerce.number().min(0),
  photoKey: z.string().trim().max(500).nullable().optional(),
  returnRequired: z.boolean(),
  active: z.boolean().default(true),
})

export const employeeSchema = z.object({
  nik: z.string().trim().min(2).max(40),
  name: z.string().trim().min(2).max(160),
  position: z.string().trim().min(2).max(120),
  departmentId: z.string().uuid(),
  contractStatus: z.enum(['permanent', 'contract', 'intern', 'inactive']),
})

export const receiptItemSchema = z.object({
  variantId: z.string().uuid(),
  quantity: z.coerce.number().positive(),
  condition: z.enum(stockConditions),
  serialNumber: z.string().trim().max(160).nullable().optional(),
  receiverName: z.string().trim().min(2).max(160),
  receiptProofKey: z.string().trim().max(500).nullable().optional(),
  notes: z.string().trim().max(1000).nullable().optional(),
})

export const purchaseSchema = z.object({
  purchaseDate: z.coerce.date(),
  receivedDate: z.coerce.date(),
  prNumber: z.string().trim().max(80).nullable().optional(),
  requestNumber: z.string().trim().max(80).nullable().optional(),
  poNumber: z.string().trim().max(80).nullable().optional(),
  deliveryNoteNumber: z.string().trim().max(80).nullable().optional(),
  invoiceNumber: z.string().trim().max(80).nullable().optional(),
  reason: z.string().trim().min(3).max(1000),
  supplierId: z.string().uuid(),
  billingProofKey: z.string().max(500).nullable().optional(),
  paymentProofKey: z.string().max(500).nullable().optional(),
  totalPaid: z.coerce.number().min(0),
  fundingSource: z.enum(['company', 'advanced']),
  paymentMethod: z.enum(['cash', 'transfer']),
  funderId: z.string().uuid().nullable().optional(),
  items: z.array(receiptItemSchema).min(1),
}).superRefine((value, ctx) => {
  if (value.fundingSource === 'advanced' && !value.funderId) {
    ctx.addIssue({ code: z.ZodIssueCode.custom, path: ['funderId'], message: 'Pihak penalang wajib dipilih' })
  }
})

export const issuanceItemSchema = z.object({
  variantId: z.string().uuid(),
  condition: z.enum(availableConditions),
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

export const stocktakeFinalizeSchema = z.object({ stocktakeId: z.string().uuid() })

export type ItemInput = z.infer<typeof itemSchema>
export type PurchaseInput = z.infer<typeof purchaseSchema>
export type IssuanceInput = z.infer<typeof issuanceSchema>
export type ReturnInput = z.infer<typeof returnSchema>
export type ReimbursementInput = z.infer<typeof reimbursementSchema>

export interface ApiResponse<T> {
  data: T
  message?: string
}

export interface PaginatedResponse<T> {
  data: T[]
  pagination: { page: number; limit: number; total: number; totalPages: number }
}
