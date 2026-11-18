import { Hono } from 'hono'
import { cors } from 'hono/cors'
import { HTTPException } from 'hono/http-exception'
import { attachDb } from './middleware/auth'
import { dashboardRoutes } from './routes/dashboard'
import { inventoryRoutes } from './routes/inventory'
import { transactionRoutes } from './routes/transactions'
import { uploadRoutes } from './routes/uploads'
import type { AppEnv } from './types'

const app = new Hono<AppEnv>()

app.use('*', async (c, next) => cors({
  origin: c.env.ALLOWED_ORIGIN || 'http://localhost:8080',
  allowHeaders: ['Authorization', 'Content-Type', 'X-Idempotency-Key'],
  allowMethods: ['GET', 'POST', 'PUT', 'PATCH', 'DELETE', 'OPTIONS'],
  credentials: true,
})(c, next))

app.get('/health', (c) => c.json({ status: 'ok', service: 'inventaris-apd-api' }))
app.use('/api/*', attachDb)
app.route('/api/dashboard', dashboardRoutes)
app.route('/api/inventory', inventoryRoutes)
app.route('/api/transactions', transactionRoutes)
app.route('/api/uploads', uploadRoutes)

app.notFound((c) => c.json({ message: 'Endpoint tidak ditemukan' }, 404))
app.onError((error, c) => {
  console.error(error)
  if (error instanceof HTTPException) return c.json({ message: error.message }, error.status)
  const message = error instanceof Error ? error.message : 'Terjadi kesalahan pada server'
  const status = /duplicate key/i.test(message) ? 409 : /stock|saldo|sisa|melebihi/i.test(message) ? 422 : 500
  return c.json({ message }, status)
})

export default app
