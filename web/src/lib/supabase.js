import { createClient } from '@supabase/supabase-js'

const url = import.meta.env.VITE_SUPABASE_URL
const anonKey = import.meta.env.VITE_SUPABASE_ANON_KEY

if (!url || !anonKey) {
  throw new Error(
    'Missing VITE_SUPABASE_URL or VITE_SUPABASE_ANON_KEY. Add them to the .env file in the project root.',
  )
}

// The browser only ever uses the public anon key. Row Level Security in the
// database decides which rows the signed-in user can see.
export const supabase = createClient(url, anonKey)
