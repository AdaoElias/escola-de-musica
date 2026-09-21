import { getSupabase } from './supabase.js';

export async function login(email, senha) {
  const sb = await getSupabase();
  const { error } = await sb.auth.signInWithPassword({ email, password: senha });
  return error;
}

export async function logout() {
  const sb = await getSupabase();
  await sb.auth.signOut();
  window.location.href = '/';
}

export async function guard() {
  const sb = await getSupabase();
  const { data } = await sb.auth.getSession();
  if (!data.session) {
    window.location.href = '/';
    return null;
  }
  return sb;
}

export async function perfil(sb) {
  const { data: { user } } = await sb.auth.getUser();
  if (!user) return null;
  const { data } = await sb
    .from('usuarios')
    .select('id, nome, perfil')
    .eq('auth_uid', user.id)
    .maybeSingle();
  return data;
}