import { Hono } from 'hono'
import { itemSchema, paginationSchema } from '@inventaris/contracts'
import { zValidator } from '@hono/zod-validator'
import type { AppEnv } from '../types'

export const inventoryRoutes = new Hono<AppEnv>()

inventoryRoutes.get('/', zValidator('query', paginationSchema), async (c) => {
  const { page, limit, search } = c.req.valid('query')
  let query = c.get('db').from('inventory_view').select('*', { count: 'exact' })
  if (search) query = query.or(`code.ilike.%${search}%,name.ilike.%${search}%,category_name.ilike.%${search}%`)
  const { data, count, error } = await query
    .order('name')
    .range((page - 1) * limit, page * limit - 1)
  if (error) throw error
  return c.json({ data, pagination: { page, limit, total: count ?? 0, totalPages: Math.ceil((count ?? 0) / limit) } })
})

inventoryRoutes.post('/items', zValidator('json', itemSchema), async (c) => {
  const input = c.req.valid('json')
  const { data, error } = await c.get('db').from('items').insert({
    code: input.code,
    name: input.name,
    category_id: input.categoryId,
    specification: input.specification,
    unit: input.unit,
    minimum_stock: input.minimumStock,
    photo_key: input.photoKey,
    return_required: input.returnRequired,
    active: input.active,
  }).select().single()
  if (error) throw error
  return c.json({ data, message: 'Barang berhasil ditambahkan' }, 201)
})

inventoryRoutes.get('/movements/:variantId', async (c) => {
  const { data, error } = await c.get('db').from('stock_movements')
    .select('*, profiles(full_name)')
    .eq('variant_id', c.req.param('variantId'))
    .order('occurred_at', { ascending: false })
    .limit(100)
  if (error) throw error
  return c.json({ data })
})
