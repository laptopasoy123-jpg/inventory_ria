import { Hono } from 'hono'
import { cors } from 'hono/cors'
import { HTTPException } from 'hono/http-exception'
import { attachDb } from './middleware/auth'
import { isSupabaseConfigured } from './lib/supabase'
import { dashboardRoutes } from './routes/dashboard'
import { masterRoutes } from './routes/master'
import { inventoryRoutes } from './routes/inventory'
import { procurementRoutes } from './routes/procurements'
import { transactionRoutes } from './routes/transactions'
import { uploadRoutes } from './routes/uploads'
import type { AppEnv } from './types'

const app = new Hono<AppEnv>()

app.use('*', async (c, next) => cors({
  origin: (origin) => {
    const raw = (c.env.ALLOWED_ORIGIN || '*').trim()
    if (!origin) return raw === '*' ? '*' : (raw.split(',')[0]?.trim() || '*')
    if (raw === '*') return origin
    const allowedList = raw.split(',').map((s) => s.trim()).filter(Boolean)
    if (allowedList.includes(origin)) return origin
    if (/^https:\/\/[a-z0-9-]+\.(pages|workers)\.dev$/i.test(origin)) return origin
    if (/^http:\/\/(localhost|127\.0\.0\.1)(:\d+)?$/.test(origin)) return origin
    return allowedList[0] || origin
  },
  allowHeaders: ['Authorization', 'Content-Type', 'X-Idempotency-Key'],
  allowMethods: ['GET', 'POST', 'PUT', 'PATCH', 'DELETE', 'OPTIONS'],
  credentials: true,
})(c, next))

app.get('/', (c) => c.json({
  status: 'ok',
  service: 'inventory-ria-api',
  mode: isSupabaseConfigured(c.env) ? 'supabase' : 'local',
  health: '/health',
}))
app.get('/health', (c) => c.json({
  status: 'ok',
  service: 'inventaris-apd-api',
  mode: isSupabaseConfigured(c.env) ? 'supabase' : 'local',
}))
app.use('/api/*', attachDb)
app.route('/api/dashboard', dashboardRoutes)
app.route('/api/master', masterRoutes)
app.route('/api/inventory', inventoryRoutes)
app.route('/api/procurements', procurementRoutes)
app.route('/api/transactions', transactionRoutes)
app.route('/api/uploads', uploadRoutes)

app.notFound((c) => c.json({ message: 'Endpoint tidak ditemukan' }, 404))
app.onError((error, c) => {
  console.error(error)
  if (error instanceof HTTPException) return c.json({ message: error.message }, error.status)
  const rawErr = error as { message?: unknown } | null
  const message =
    error instanceof Error
      ? error.message
      : typeof rawErr?.message === 'string' && rawErr.message
        ? rawErr.message
        : 'Terjadi kesalahan pada server'
  const status = /duplicate key/i.test(message) ? 409 : /stock|stok|saldo|sisa|melebihi/i.test(message) ? 422 : 500
  return c.json({ message }, status)
})

export default app
