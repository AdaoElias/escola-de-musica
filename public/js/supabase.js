// Cliente Supabase vendorizado localmente (mesma versão do package.json: 2.45.0).
// Sem CDN no caminho crítico de runtime: public/js/vendor/*.esm.js
import { createClient } from './vendor/supabase-supabase-js-2.45.0.esm.js';

let client = null;

export async function getSupabase() {
  if (client) return client;
  const res = await fetch('/api/client-config');
  const cfg = await res.json();
  client = createClient(cfg.supabaseUrl, cfg.supabaseKey);
  return client;
}