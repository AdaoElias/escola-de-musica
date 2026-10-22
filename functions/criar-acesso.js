const { createClient } = require('@supabase/supabase-js');

const URL = process.env.SUPABASE_URL || process.env.VITE_SUPABASE_URL;
const SERVICE = process.env.SUPABASE_SERVICE_ROLE_KEY;
const ANON = process.env.SUPABASE_PUBLISHABLE_KEY || process.env.SUPABASE_ANON_KEY;

function json(code, obj) {
  return {
    statusCode: code,
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify(obj),
  };
}

function traduz(msg) {
  if (/already registered|already been registered/i.test(msg)) {
    return 'Já existe uma conta com este e-mail.';
  }
  return msg;
}

exports.handler = async (event) => {
  if (event.httpMethod !== 'POST') return json(405, { error: 'Método não permitido.' });
  if (!URL || !SERVICE || !ANON) {
    return json(500, { error: 'Servidor sem SUPABASE_SERVICE_ROLE_KEY configurada.' });
  }

  const auth = event.headers.authorization || event.headers.Authorization || '';
  const token = auth.startsWith('Bearer ') ? auth.slice(7) : '';
  if (!token) return json(401, { error: 'Não autenticado.' });

  let body;
  try {
    body = JSON.parse(event.body || '{}');
  } catch {
    return json(400, { error: 'JSON inválido.' });
  }

  const admin = createClient(URL, SERVICE, { auth: { persistSession: false } });

  const { data: userData, error: userErr } = await admin.auth.getUser(token);
  if (userErr || !userData || !userData.user) return json(401, { error: 'Sessão inválida.' });

  const { data: eu, error: euErr } = await admin
    .from('usuarios')
    .select('id, perfil')
    .eq('auth_uid', userData.user.id)
    .maybeSingle();
  if (euErr) return json(500, { error: euErr.message });
  if (!eu || eu.perfil !== 'admin') {
    return json(403, { error: 'Apenas administradores podem gerenciar acessos.' });
  }

  const professorId = Number(body.professor_id);
  if (!professorId) return json(400, { error: 'professor_id obrigatório.' });

  const { data: prof, error: profErr } = await admin
    .from('professores')
    .select('id, nome, email, usuario_id')
    .eq('id', professorId)
    .maybeSingle();
  if (profErr) return json(500, { error: profErr.message });
  if (!prof) return json(404, { error: 'Professor não encontrado.' });

  const email = (body.email || prof.email || '').trim().toLowerCase();
  if (!email) return json(400, { error: 'Informe o e-mail do professor.' });

  const acao = body.acao || 'criar';
  let authUserId = null;

  if (acao === 'criar') {
    const senha = (body.senha || '').trim();
    if (senha.length < 6) {
      return json(400, { error: 'A senha temporária deve ter ao menos 6 caracteres.' });
    }
    const { data: novo, error } = await admin.auth.admin.createUser({
      email,
      password: senha,
      email_confirm: true,
      user_metadata: { full_name: prof.nome },
    });
    if (error) return json(400, { error: traduz(error.message) });
    authUserId = novo.user.id;
  } else if (acao === 'vincular') {
    let page = 1;
    let encontrado = null;
    while (page <= 10 && !encontrado) {
      const { data, error } = await admin.auth.admin.listUsers({ page, perPage: 200 });
      if (error) return json(500, { error: error.message });
      const users = (data && data.users) || [];
      encontrado = users.find((u) => (u.email || '').toLowerCase() === email) || null;
      if (users.length < 200) break;
      page++;
    }
    if (!encontrado) return json(404, { error: 'Nenhuma conta encontrada com este e-mail.' });
    authUserId = encontrado.id;
  } else {
    return json(400, { error: 'Ação inválida.' });
  }

  const { data: existente, error: exErr } = await admin
    .from('usuarios')
    .select('id')
    .eq('auth_uid', authUserId)
    .maybeSingle();
  if (exErr) return json(500, { error: exErr.message });

  let usuarioId;
  if (existente) {
    const { error } = await admin
      .from('usuarios')
      .update({ nome: prof.nome, email })
      .eq('id', existente.id);
    if (error) return json(500, { error: error.message });
    usuarioId = existente.id;
  } else {
    const { data: criado, error } = await admin
      .from('usuarios')
      .insert({ auth_uid: authUserId, nome: prof.nome, email, perfil: 'professor', ativo: true })
      .select('id')
      .single();
    if (error) return json(500, { error: error.message });
    usuarioId = criado.id;
  }

  const { error: linkErr } = await admin
    .from('professores')
    .update({ usuario_id: usuarioId })
    .eq('id', prof.id);
  if (linkErr) return json(500, { error: linkErr.message });

  return json(200, { ok: true, usuario_id: usuarioId });
};
