import { Hono } from 'hono'
import { zValidator } from '@hono/zod-validator'
import {
  issuanceSchema,
  purchaseSchema,
  reimbursementSchema,
  returnSchema,
  stocktakeCreateSchema,
  stocktakeFinalizeSchema,
} from '@inventaris/contracts'
import type { AppEnv } from '../types'

export const transactionRoutes = new Hono<AppEnv>()

transactionRoutes.get('/purchases', async (c) => {
  const data = await c.get('service').listPurchases({
    fundingSource: c.req.query('fundingSource'),
    search: c.req.query('search'),
  })
  return c.json({ data })
})

transactionRoutes.post('/purchases', zValidator('json', purchaseSchema), async (c) => {
  const key = c.req.header('X-Idempotency-Key') || crypto.randomUUID()
  const data = await c.get('service').createPurchaseReceipt(c.req.valid('json'), key)
  return c.json({ data, message: 'Barang masuk berhasil disimpan dan menambah stok' }, 201)
})

transactionRoutes.put('/purchases/:id', zValidator('json', purchaseSchema), async (c) => {
  const data = await c.get('service').updatePurchaseReceipt(c.req.param('id'), c.req.valid('json'))
  return c.json({ data, message: 'Barang masuk berhasil diperbarui & stok disesuaikan' })
})

transactionRoutes.delete('/purchases/:id', async (c) => {
  await c.get('service').deletePurchaseReceipt(c.req.param('id'))
  return c.json({ message: 'Barang masuk berhasil dihapus & stok disesuaikan' })
})

transactionRoutes.get('/issuances', async (c) => {
  const data = await c.get('service').listIssuances({
    search: c.req.query('search'),
    employeeId: c.req.query('employeeId'),
  })
  return c.json({ data })
})

transactionRoutes.get('/issuances/open-by-employee/:employeeId', async (c) => {
  const data = await c.get('service').listOpenIssuanceItemsByEmployee(c.req.param('employeeId'))
  return c.json({ data })
})

transactionRoutes.post('/issuances', zValidator('json', issuanceSchema), async (c) => {
  const key = c.req.header('X-Idempotency-Key') || crypto.randomUUID()
  const data = await c.get('service').createIssuance(c.req.valid('json'), key)
  return c.json({ data, message: 'Barang keluar berhasil dicatat & mengurangi stok tersedia' }, 201)
})

transactionRoutes.put('/issuances/:id', zValidator('json', issuanceSchema), async (c) => {
  const data = await c.get('service').updateIssuance(c.req.param('id'), c.req.valid('json'))
  return c.json({ data, message: 'Barang keluar berhasil diperbarui & stok disesuaikan' })
})

transactionRoutes.delete('/issuances/:id', async (c) => {
  await c.get('service').deleteIssuance(c.req.param('id'))
  return c.json({ message: 'Barang keluar berhasil dihapus & stok dikembalikan' })
})

transactionRoutes.get('/returns', async (c) => {
  const data = await c.get('service').listReturns({
    result: c.req.query('result'),
    search: c.req.query('search'),
  })
  return c.json({ data })
})

transactionRoutes.post('/returns', zValidator('json', returnSchema), async (c) => {
  const key = c.req.header('X-Idempotency-Key') || crypto.randomUUID()
  const data = await c.get('service').createReturn(c.req.valid('json'), key)
  return c.json({ data, message: 'Pengembalian APD berhasil diproses' }, 201)
})

transactionRoutes.put('/returns/:id', zValidator('json', returnSchema), async (c) => {
  const data = await c.get('service').updateReturn(c.req.param('id'), c.req.valid('json'))
  return c.json({ data, message: 'Pengembalian APD berhasil diperbarui' })
})

transactionRoutes.delete('/returns/:id', async (c) => {
  await c.get('service').deleteReturn(c.req.param('id'))
  return c.json({ message: 'Pengembalian APD berhasil dihapus & stok disesuaikan' })
})

transactionRoutes.get('/liabilities', async (c) => {
  const data = await c.get('service').getEmployeeLiabilities()
  return c.json({ data })
})

transactionRoutes.get('/stocktakes', async (c) => {
  const data = await c.get('service').listStocktakes({ status: c.req.query('status') })
  return c.json({ data })
})

transactionRoutes.post('/stocktakes', zValidator('json', stocktakeCreateSchema), async (c) => {
  const data = await c.get('service').createStocktake(c.req.valid('json'))
  return c.json({ data, message: 'Stok opname berhasil disimpan' }, 201)
})

transactionRoutes.put('/stocktakes/:id', zValidator('json', stocktakeCreateSchema), async (c) => {
  const data = await c.get('service').updateStocktake(c.req.param('id'), c.req.valid('json'))
  return c.json({ data, message: 'Stok opname berhasil diperbarui' })
})

transactionRoutes.delete('/stocktakes/:id', async (c) => {
  await c.get('service').deleteStocktake(c.req.param('id'))
  return c.json({ message: 'Stok opname berhasil dihapus & stok disesuaikan' })
})

transactionRoutes.post('/stocktakes/finalize', zValidator('json', stocktakeFinalizeSchema), async (c) => {
  const data = await c.get('service').finalizeStocktake(c.req.valid('json').stocktakeId)
  return c.json({ data, message: 'Stok opname berhasil difinalisasi & stok disesuaikan' })
})

transactionRoutes.post('/reimbursements', zValidator('json', reimbursementSchema), async (c) => {
  const data = await c.get('service').createReimbursement(c.req.valid('json'))
  return c.json({ data, message: 'Penggantian dana berhasil dicatat' }, 201)
})
