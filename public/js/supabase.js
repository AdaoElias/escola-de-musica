import { createClient } from 'https://esm.sh/@supabase/supabase-js@2.45.0';

let client = null;

export async function getSupabase() {
  if (client) return client;
  const res = await fetch('/api/client-config');
  const cfg = await res.json();
  client = createClient(cfg.supabaseUrl, cfg.supabaseKey);
  return client;
}