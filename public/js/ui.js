export function toast(mensagem, tipo = 'ok') {
  let box = document.querySelector('.toasts');
  if (!box) {
    box = document.createElement('div');
    box.className = 'toasts';
    document.body.appendChild(box);
  }
  const el = document.createElement('div');
  el.className = 'toast ' + (tipo === 'erro' ? 'erro' : 'ok');
  el.textContent = mensagem;
  box.appendChild(el);
  setTimeout(() => {
    el.style.opacity = '0';
    el.style.transition = 'opacity 0.3s';
    setTimeout(() => el.remove(), 320);
  }, 3200);
}

export function ligaFecharModais(modal) {
  for (const el of document.querySelectorAll('[data-fechar]')) {
    el.addEventListener('click', () => modal.close());
  }
}

export function ligaMascaraTelefone(input) {
  input.addEventListener('input', () => {
    const d = input.value.replace(/\D/g, '').slice(0, 11);
    if (d.length <= 10) {
      input.value = d.length > 6 ? d.replace(/^(\d{2})(\d{4})(\d{0,4})$/, '($1) $2-$3')
        : d.length > 2 ? d.replace(/^(\d{2})(\d{0,4})$/, '($1) $2')
        : d.replace(/^(\d{0,2})$/, d.length === 2 ? '($1)' : '$1');
    } else {
      input.value = d.replace(/^(\d{2})(\d{5})(\d{0,4})$/, '($1) $2-$3');
    }
  });
}

export function emailValido(valor) {
  const v = (valor || '').trim();
  return !v || /^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(v);
}

export function ligaMascaraCpf(input) {
  input.addEventListener('input', () => {
    const d = input.value.replace(/\D/g, '').slice(0, 11);
    input.value = d.length > 9 ? d.replace(/^(\d{3})(\d{3})(\d{3})(\d{0,2})$/, '$1.$2.$3-$4')
      : d.length > 6 ? d.replace(/^(\d{3})(\d{3})(\d{0,3})$/, '$1.$2.$3')
      : d.length > 3 ? d.replace(/^(\d{3})(\d{0,3})$/, '$1.$2')
      : d;
  });
}

export function formatarCpf(cpf) {
  const d = (cpf || '').replace(/\D/g, '').slice(0, 11);
  return d ? d.replace(/^(\d{3})(\d{3})(\d{3})(\d{0,2})$/, '$1.$2.$3-$4') : '';
}

// Traduz erros do Postgres (Supabase) em mensagens amigáveis.
export function erroAmigo(error) {
  const msg = (error && error.message) || String(error || '');
  const codigo = (error && error.code) || (msg.match(/([0-9A-Z]{5}):/) || [])[1] || '';
  if (codigo === '23505') {
    if (msg.includes('cpf')) return 'Já existe um cadastro com este CPF.';
    if (msg.includes('email')) return 'Já existe um cadastro com este e-mail.';
    if (msg.includes('matricula')) return 'Matrícula duplicada: este aluno já está registrado nesta turma / com este professor.';
    return 'Registro duplicado.';
  }
  if (codigo === '23514') {
    if (msg.includes('cpf_valido')) return 'CPF inválido (dígitos verificadores não conferem).';
    if (msg.includes('financeiro_check_valor')) return 'Valor inválido para este tipo de lançamento.';
    return 'Valor ou campo inválido para esta operação.';
  }
  if (codigo === '23503') return 'Registro vinculado não existe.';
  if (msg.includes('turma(s) ativa(s)') || msg.includes('Turma ativa exige professor ativo')) {
    return 'Regra de turmas: só é possível inativar um professor sem turmas ativas, e turma ativa exige professor ativo. Encerre ou transfira a turma.';
  }
  return 'Erro: ' + msg;
}

// Valida os dígitos verificadores do CPF (aceita vazio = ok).
export function cpfValido(valor) {
  const d = (valor || '').replace(/\D/g, '');
  if (!d) return true;
  if (d.length !== 11) return false;
  if (/^(\d)\1{10}$/.test(d)) return false;
  let soma = 0;
  for (let i = 0; i < 9; i++) soma += Number(d[i]) * (10 - i);
  let dv = (soma * 10) % 11;
  if (dv === 10) dv = 0;
  if (dv !== Number(d[9])) return false;
  soma = 0;
  for (let i = 0; i < 10; i++) soma += Number(d[i]) * (11 - i);
  dv = (soma * 10) % 11;
  if (dv === 10) dv = 0;
  return dv === Number(d[10]);
}

export function formatarDataBr(iso) {
  if (!iso) return '—';
  const [a, m, d] = iso.slice(0, 10).split('-');
  return a && m && d ? d + '/' + m + '/' + a : iso;
}

export async function buscarCep(cepInput) {
  const digitos = (cepInput.value || '').replace(/\D/g, '').slice(0, 8);
  cepInput.value = digitos ? digitos.replace(/^(\d{5})(\d{3})$/, '$1-$2') : '';
  if (digitos.length !== 8) return null;
  try {
    const r = await fetch('https://viacep.com.br/ws/' + digitos + '/json/');
    const j = await r.json();
    if (j.erro) return null;
    return {
      endereco: j.logradouro || '',
      bairro: j.bairro || '',
      cidade: j.localidade || '',
      uf: j.uf || '',
    };
  } catch {
    return null;
  }
}