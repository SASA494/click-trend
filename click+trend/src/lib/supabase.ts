import { createClient } from '@supabase/supabase-js'

const url = import.meta.env.VITE_SUPABASE_URL
const key = import.meta.env.VITE_SUPABASE_ANON_KEY
export const isSupabaseConfigured = Boolean(url && key)
export const supabase = url && key ? createClient(url, key) : null

export type Role = 'super_admin' | 'sales' | 'content_manager' | 'viewer'
export type Profile = { id: string; full_name: string | null; role: Role; account_type: 'client' | 'staff' }
