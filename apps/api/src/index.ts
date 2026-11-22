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
    const allowed = c.env.ALLOWED_ORIGIN || 'http://localhost:8081'
    if (!origin) return allowed
    if (origin === allowed) return origin
    if (/^http:\/\/(localhost|127\.0\.0\.1)(:\d+)?$/.test(origin)) return origin
    return allowed
  },
  allowHeaders: ['Authorization', 'Content-Type', 'X-Idempotency-Key'],
  allowMethods: ['GET', 'POST', 'PUT', 'PATCH', 'DELETE', 'OPTIONS'],
  credentials: true,
})(c, next))

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
  const message = error instanceof Error ? error.message : 'Terjadi kesalahan pada server'
  const status = /duplicate key/i.test(message) ? 409 : /stock|stok|saldo|sisa|melebihi/i.test(message) ? 422 : 500
  return c.json({ message }, status)
})

export default app
