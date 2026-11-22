import { createMiddleware } from 'hono/factory'
import { createAdminClient, isSupabaseConfigured } from '../lib/supabase'
import { SupabaseInventoryService } from '../lib/supabase-service'
import { LocalInventoryService } from '../lib/local-service'
import type { AppEnv } from '../types'

export const attachDb = createMiddleware<AppEnv>(async (c, next) => {
  if (isSupabaseConfigured(c.env)) {
    const db = createAdminClient(c.env)
    c.set('db', db)
    c.set('mode', 'supabase')
    c.set('service', new SupabaseInventoryService(db))
  } else {
    c.set('db', null)
    c.set('mode', 'local')
    c.set('service', new LocalInventoryService(c.env.ATTACHMENTS))
  }
  await next()
})
