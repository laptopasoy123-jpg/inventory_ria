import type { SupabaseClient } from '@supabase/supabase-js'

export interface Env {
  SUPABASE_URL: string
  SUPABASE_PUBLISHABLE_KEY?: string
  SUPABASE_SECRET_KEY?: string
  SUPABASE_ANON_KEY?: string
  SUPABASE_SERVICE_ROLE_KEY?: string
  ALLOWED_ORIGIN: string
  ATTACHMENTS: R2Bucket
}

export type AppVariables = {
  db: SupabaseClient
}

export type AppEnv = { Bindings: Env; Variables: AppVariables }
