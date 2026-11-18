import { createMiddleware } from 'hono/factory'
import { createAdminClient } from '../lib/supabase'
import type { AppEnv } from '../types'

export const attachDb = createMiddleware<AppEnv>(async (c, next) => {
  c.set('db', createAdminClient(c.env))
  await next()
})
