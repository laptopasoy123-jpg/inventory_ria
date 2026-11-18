import { Hono } from 'hono'
import { zValidator } from '@hono/zod-validator'
import type { SupabaseClient } from '@supabase/supabase-js'
import { issuanceSchema, purchaseSchema, reimbursementSchema, returnSchema, stocktakeFinalizeSchema } from '@inventaris/contracts'
import type { AppEnv } from '../types'

export const transactionRoutes = new Hono<AppEnv>()

async function resolveActorId(db: SupabaseClient): Promise<string | null> {
  const { data } = await db.from('profiles').select('id').eq('active', true).order('created_at').limit(1).maybeSingle()
  return data?.id ?? null
}

transactionRoutes.post('/purchases', zValidator('json', purchaseSchema), async (c) => {
  const db = c.get('db')
  const payload = { ...c.req.valid('json'), idempotencyKey: c.req.header('X-Idempotency-Key') || crypto.randomUUID() }
  const { data, error } = await db.rpc('create_purchase_receipt', { p_payload: payload, p_actor: await resolveActorId(db) })
  if (error) throw error
  return c.json({ data, message: 'Pembelian dan penerimaan berhasil disimpan' }, 201)
})

transactionRoutes.post('/issuances', zValidator('json', issuanceSchema), async (c) => {
  const db = c.get('db')
  const payload = { ...c.req.valid('json'), idempotencyKey: c.req.header('X-Idempotency-Key') || crypto.randomUUID() }
  const { data, error } = await db.rpc('create_issuance', { p_payload: payload, p_actor: await resolveActorId(db) })
  if (error) throw error
  return c.json({ data, message: 'Barang keluar berhasil dicatat' }, 201)
})

transactionRoutes.post('/returns', zValidator('json', returnSchema), async (c) => {
  const db = c.get('db')
  const payload = { ...c.req.valid('json'), idempotencyKey: c.req.header('X-Idempotency-Key') || crypto.randomUUID() }
  const { data, error } = await db.rpc('create_return', { p_payload: payload, p_actor: await resolveActorId(db) })
  if (error) throw error
  return c.json({ data, message: 'Pengembalian berhasil diperiksa' }, 201)
})

transactionRoutes.post('/reimbursements', zValidator('json', reimbursementSchema), async (c) => {
  const db = c.get('db')
  const { data, error } = await db.rpc('create_reimbursement', { p_payload: c.req.valid('json'), p_actor: await resolveActorId(db) })
  if (error) throw error
  return c.json({ data, message: 'Penggantian dana berhasil dicatat' }, 201)
})

transactionRoutes.post('/stocktakes/finalize', zValidator('json', stocktakeFinalizeSchema), async (c) => {
  const db = c.get('db')
  const { data, error } = await db.rpc('finalize_stocktake', { p_stocktake_id: c.req.valid('json').stocktakeId, p_actor: await resolveActorId(db) })
  if (error) throw error
  return c.json({ data, message: 'Stok opname berhasil difinalisasi' })
})
