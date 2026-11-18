import { Hono } from 'hono'
import type { AppEnv } from '../types'

export const dashboardRoutes = new Hono<AppEnv>()

dashboardRoutes.get('/', async (c) => {
  const db = c.get('db')
  const month = Number(c.req.query('month') || new Date().getMonth() + 1)
  const year = Number(c.req.query('year') || new Date().getFullYear())
  const { data, error } = await db.rpc('dashboard_summary', { p_month: month, p_year: year })
  if (error) throw error
  return c.json({ data })
})
