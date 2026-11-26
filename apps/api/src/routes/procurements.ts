import { Hono } from 'hono'
import { zValidator } from '@hono/zod-validator'
import { procurementPaymentSchema, procurementSchema } from '@inventaris/contracts'
import { z } from 'zod'
import type { AppEnv } from '../types'

export const procurementRoutes = new Hono<AppEnv>()

procurementRoutes.get('/', async (c) => {
  const data = await c.get('service').listProcurements({
    status: c.req.query('status'),
    paymentStatus: c.req.query('paymentStatus'),
    search: c.req.query('search'),
    variantId: c.req.query('variantId'),
    onlyPendingReceipt: c.req.query('pending') === 'true',
  })
  return c.json({ data })
})

procurementRoutes.get('/payments/all', async (c) => {
  const data = await c.get('service').listPayments()
  return c.json({ data })
})

procurementRoutes.get('/:id', async (c) => {
  const data = await c.get('service').getProcurement(c.req.param('id'))
  return c.json({ data })
})

procurementRoutes.post('/', zValidator('json', procurementSchema), async (c) => {
  const key = c.req.header('X-Idempotency-Key') || crypto.randomUUID()
  const data = await c.get('service').createProcurement(c.req.valid('json'), key)
  return c.json({ data, message: 'Pengadaan barang berhasil dibuat' }, 201)
})

procurementRoutes.put('/:id', zValidator('json', procurementSchema), async (c) => {
  const data = await c.get('service').updateProcurement(c.req.param('id'), c.req.valid('json'))
  return c.json({ data, message: 'Pengadaan barang berhasil diperbarui' })
})

procurementRoutes.delete('/:id', async (c) => {
  await c.get('service').deleteProcurement(c.req.param('id'))
  return c.json({ message: 'Pengadaan barang berhasil dihapus' })
})

procurementRoutes.patch(
  '/:id/status',
  zValidator('json', z.object({
    status: z.enum(['ordered', 'cancelled']),
    cancelNote: z.string().trim().max(1000).optional(),
  })),
  async (c) => {
    const body = c.req.valid('json')
    await c.get('service').updateProcurementStatus(c.req.param('id'), body.status, body.cancelNote)
    return c.json({ message: body.status === 'cancelled' ? 'Pengadaan berhasil dibatalkan' : 'Pengadaan berhasil diaktifkan kembali' })
  },
)

procurementRoutes.post('/payments', zValidator('json', procurementPaymentSchema), async (c) => {
  const data = await c.get('service').createProcurementPayment(c.req.valid('json'))
  return c.json({ data, message: 'Pembayaran pengadaan berhasil dicatat' }, 201)
})

procurementRoutes.put('/payments/:id', zValidator('json', procurementPaymentSchema), async (c) => {
  const data = await c.get('service').updateProcurementPayment(c.req.param('id'), c.req.valid('json'))
  return c.json({ data, message: 'Pembayaran pengadaan berhasil diperbarui' })
})

procurementRoutes.delete('/payments/:id', async (c) => {
  await c.get('service').deleteProcurementPayment(c.req.param('id'))
  return c.json({ message: 'Pembayaran pengadaan berhasil dihapus' })
})
