import { Hono } from 'hono'
import type { AppEnv } from '../types'

export const dashboardRoutes = new Hono<AppEnv>()

dashboardRoutes.get('/', async (c) => {
  const month = Number(c.req.query('month') || new Date().getMonth() + 1)
  const year = Number(c.req.query('year') || new Date().getFullYear())
  const data = await c.get('service').getDashboard(month, year)
  return c.json({ data, mode: c.get('mode') })
})
