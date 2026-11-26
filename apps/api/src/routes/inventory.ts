import { Hono } from 'hono'
import { conditionTransferSchema, itemSchema, openingStockSchema, paginationSchema } from '@inventaris/contracts'
import { zValidator } from '@hono/zod-validator'
import type { AppEnv } from '../types'

export const inventoryRoutes = new Hono<AppEnv>()

inventoryRoutes.get('/', zValidator('query', paginationSchema), async (c) => {
  const { page, limit, search } = c.req.valid('query')
  const status = c.req.query('status')
  const categoryId = c.req.query('categoryId')
  const result = await c.get('service').listInventory({ page, limit, search, status, categoryId })
  return c.json(result)
})

inventoryRoutes.post('/items', zValidator('json', itemSchema), async (c) => {
  const data = await c.get('service').saveItem(null, c.req.valid('json'))
  return c.json({ data, message: 'Barang berhasil ditambahkan' }, 201)
})

inventoryRoutes.get('/movements', async (c) => {
  const limit = Number(c.req.query('limit') || 150)
  const data = await c.get('service').listMovements({ limit })
  return c.json({ data })
})

inventoryRoutes.get('/movements/:variantId', async (c) => {
  const data = await c.get('service').listMovements({ variantId: c.req.param('variantId'), limit: 100 })
  return c.json({ data })
})

inventoryRoutes.get('/opening-stocks', async (c) => {
  const data = await c.get('service').listOpeningStocks()
  return c.json({ data })
})

inventoryRoutes.post('/opening-stock', zValidator('json', openingStockSchema), async (c) => {
  const key = c.req.header('X-Idempotency-Key') || crypto.randomUUID()
  const data = await c.get('service').createOpeningStock(c.req.valid('json'), key)
  return c.json({ data, message: 'Stok awal berhasil dicatat ke inventaris' }, 201)
})

inventoryRoutes.put('/opening-stock/:id', zValidator('json', openingStockSchema), async (c) => {
  const data = await c.get('service').updateOpeningStock(c.req.param('id'), c.req.valid('json'))
  return c.json({ data, message: 'Stok awal berhasil diperbarui' })
})

inventoryRoutes.delete('/opening-stock/:id', async (c) => {
  await c.get('service').deleteOpeningStock(c.req.param('id'))
  return c.json({ message: 'Stok awal berhasil dihapus & stok disesuaikan' })
})

inventoryRoutes.post('/condition-transfer', zValidator('json', conditionTransferSchema), async (c) => {
  const data = await c.get('service').transferCondition(c.req.valid('json'))
  return c.json({ data, message: 'Kondisi stok berhasil diperbarui' }, 201)
})
