import { createClient } from '@supabase/supabase-js'
import type { Env } from '../types'

function requiredKey(value: string | undefined, name: string): string {
  if (!value) throw new Error(`Environment variable ${name} belum dikonfigurasi`)
  return value
}

export const createAdminClient = (env: Env) => createClient(
  env.SUPABASE_URL,
  requiredKey(env.SUPABASE_SECRET_KEY || env.SUPABASE_SERVICE_ROLE_KEY, 'SUPABASE_SECRET_KEY'),
  {
    auth: { autoRefreshToken: false, persistSession: false },
  },
)
