import { guard, logout, perfil } from './auth.js';
import { toast, ligaFecharModais, buscarCep, ligaMascaraTelefone, emailValido, ligaMascaraCpf, formatarCpf, formatarDataBr, cpfValido, erroAmigo } from './ui.js';
import { popularInstrumentos, popularFormacoes } from './instrumentos.js';

const sb = await guard();
if (!sb) throw new Error('redirecionado');

const tbody = document.getElementById('tbody');
const modal = document.getElementById('modal');
const form = document.getElementById('form');
const erro = document.getElementById('erro');
const salvarBtn = document.getElementById('btn-salvar');
let editando = null;

const me = await perfil(sb);

document.getElementById('sair').addEventListener('click', logout);
for (const el of document.querySelectorAll('[data-futuro]')) {
  el.addEventListener('click', (e) => e.preventDefault());
}

async function carregar() {
  const { data, error } = await sb.from('professores').select('*').order('nome');
  if (error) return mostrarErroTabela(error.message);
  tbody.innerHTML = '';
  for (const p of data) {
    const tr = document.createElement('tr');
    tr.innerHTML = `
      <td>${p.nome}</td>
      <td>${formatarCpf(p.cpf) || '—'}</td>
      <td>${formatarDataBr(p.nascimento)}</td>
      <td>${p.instrumento || '—'}</td>
      <td>${p.email || '—'}</td>
      <td>${p.telefone || '—'}</td>
      <td>${p.cidade || '—'}</td>
      <td>${p.usuario_id ? '<span class="badge b-ok">Vinculado</span>' : '<span class="badge b-mut">Sem acesso</span>'}</td>
      <td>${p.ativo ? '<span class="badge b-ok">Ativo</span>' : '<span class="badge b-mut">Inativo</span>'}</td>
      <td class="acoes">
        ${p.ativo ? '<button class="mini" data-editar="' + p.id + '">Editar</button>' : ''}
        ${p.ativo ? '<button class="mini danger" data-inativar="' + p.id + '">Inativar</button>' : ''}
      </td>`;
    tbody.appendChild(tr);
  }
  if (!data.length) {
    tbody.innerHTML = '<tr><td colspan="10" class="empty">Nenhum professor cadastrado ainda.</td></tr>';
  }
}

function mostrarErroTabela(msg) {
  const tr = document.createElement('tr');
  tr.innerHTML = '<td colspan="10" class="error">Erro ao carregar: ' + msg + '</td>';
  tbody.appendChild(tr);
}

function abrirModal(prof = null) {
  erro.textContent = '';
  salvarBtn.disabled = false;
  editando = prof;
  document.getElementById('titulo-modal').textContent = prof ? 'Editar professor' : 'Novo professor';
  document.getElementById('id').value = prof ? prof.id : '';
  document.getElementById('nome').value = prof ? prof.nome : '';
  document.getElementById('cpf').value = prof ? formatarCpf(prof.cpf) : '';
  document.getElementById('nascimento').value = prof ? (prof.nascimento || '') : '';
  document.getElementById('instrumento').value = prof ? (prof.instrumento || '') : '';
  document.getElementById('email').value = prof ? (prof.email || '') : '';
  document.getElementById('telefone').value = prof ? (prof.telefone || '') : '';
  document.getElementById('formacao').value = prof ? (prof.formacao || '') : '';
  document.getElementById('cep').value = prof ? (prof.cep || '') : '';
  document.getElementById('endereco').value = prof ? (prof.endereco || '') : '';
  document.getElementById('bairro').value = prof ? (prof.bairro || '') : '';
  document.getElementById('cidade').value = prof ? (prof.cidade || '') : '';
  document.getElementById('ativo').checked = prof ? prof.ativo : true;
  renderAcesso(prof);
  modal.showModal();
}

function renderAcesso(prof) {
  const box = document.getElementById('acesso-box');
  if (prof && prof.usuario_id) {
    box.innerHTML = '<span class="badge b-ok">Acesso vinculado</span> '
      + '<span class="recentes-sub">Este professor já pode entrar no sistema.</span>';
    return;
  }
  box.innerHTML = `
    <label class="check"><input type="checkbox" id="criar-acesso"> Criar acesso para este professor</label>
    <label class="field" id="senha-acesso-campo" hidden>Senha temporária
      <input type="password" id="senha-acesso" minlength="6" autocomplete="new-password">
      <small>mínimo de 6 caracteres — o professor pode trocar depois em "Senha"</small>
    </label>
    <p class="sub">O acesso usa o e-mail informado acima. Sem e-mail não é possível criar.</p>`;
  const chk = box.querySelector('#criar-acesso');
  const campo = box.querySelector('#senha-acesso-campo');
  chk.addEventListener('change', () => { campo.hidden = !chk.checked; });
}

async function preencherEndereco() {
  const res = await buscarCep(document.getElementById('cep'));
  if (!res) return toast('CEP não encontrado. Digite o endereço manualmente.', 'erro');
  document.getElementById('endereco').value = res.endereco;
  document.getElementById('bairro').value = res.bairro;
  document.getElementById('cidade').value = res.cidade;
  if (!res.cidade) document.getElementById('cidade').value = res.uf;
}

document.getElementById('novo').addEventListener('click', () => abrirModal());
document.getElementById('buscar-cep').addEventListener('click', preencherEndereco);
document.getElementById('cep').addEventListener('blur', () => {
  if ((document.getElementById('cep').value || '').replace(/\D/g, '').length === 8) preencherEndereco();
});
document.getElementById('cep').addEventListener('keydown', (e) => {
  if (e.key === 'Enter') {
    e.preventDefault();
    preencherEndereco();
  }
});

ligaMascaraTelefone(document.getElementById('telefone'));
ligaMascaraCpf(document.getElementById('cpf'));
popularFormacoes();
document.getElementById('cancelar').addEventListener('click', () => modal.close());
ligaFecharModais(modal);

form.addEventListener('submit', async (e) => {
  e.preventDefault();
  erro.textContent = '';
  salvarBtn.disabled = true;
  const dados = {
    nome: document.getElementById('nome').value.trim(),
    cpf: document.getElementById('cpf').value.trim() || null,
    nascimento: document.getElementById('nascimento').value || null,
    instrumento: document.getElementById('instrumento').value.trim() || null,
    email: document.getElementById('email').value.trim() || null,
    telefone: document.getElementById('telefone').value.trim() || null,
    formacao: document.getElementById('formacao').value.trim() || null,
    cep: document.getElementById('cep').value.trim() || null,
    endereco: document.getElementById('endereco').value.trim() || null,
    bairro: document.getElementById('bairro').value.trim() || null,
    cidade: document.getElementById('cidade').value.trim() || null,
    ativo: document.getElementById('ativo').checked,
  };
  if (!dados.nome) {
    salvarBtn.disabled = false;
    return;
  }
  if (!emailValido(dados.email)) {
    erro.textContent = 'E-mail inválido (deve conter @).';
    salvarBtn.disabled = false;
    return;
  }
  if (dados.cpf && !cpfValido(dados.cpf)) {
    erro.textContent = 'CPF do professor inválido (dígitos verificadores não conferem).';
    salvarBtn.disabled = false;
    return;
  }

  const chkAcesso = document.getElementById('criar-acesso');
  const criarAcesso = !!(chkAcesso && chkAcesso.checked);
  const senhaAcesso = criarAcesso ? (document.getElementById('senha-acesso').value || '') : '';
  if (criarAcesso) {
    if (!dados.email) {
      erro.textContent = 'Informe o e-mail para criar o acesso.';
      salvarBtn.disabled = false;
      return;
    }
    if (senhaAcesso.length < 6) {
      erro.textContent = 'A senha temporária deve ter ao menos 6 caracteres.';
      salvarBtn.disabled = false;
      return;
    }
  }

  const salvo = editando
    ? await sb.from('professores').update(dados).eq('id', editando.id).select('id').single()
    : await sb.from('professores').insert(dados).select('id').single();

  if (salvo.error) {
    erro.textContent = erroAmigo(salvo.error);
    salvarBtn.disabled = false;
    return;
  }
  const professorId = editando ? editando.id : salvo.data.id;

  if (criarAcesso) {
    try {
      const { data: { session } } = await sb.auth.getSession();
      const resp = await fetch('/api/criar-acesso', {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          Authorization: 'Bearer ' + (session ? session.access_token : ''),
        },
        body: JSON.stringify({
          professor_id: professorId,
          email: dados.email,
          senha: senhaAcesso,
          acao: 'criar',
        }),
      });
      const j = await resp.json().catch(() => ({}));
      if (!resp.ok) throw new Error(j.error || 'Falha ao criar o acesso.');
    } catch (err) {
      erro.textContent = 'Professor salvo, mas o acesso falhou: ' + err.message;
      salvarBtn.disabled = false;
      carregar();
      return;
    }
  }

  modal.close();
  toast(criarAcesso ? 'Professor e acesso criados.' : (editando ? 'Professor atualizado.' : 'Professor cadastrado.'));
  carregar();
});

tbody.addEventListener('click', async (e) => {
  const btnEditar = e.target.closest('[data-editar]');
  const btnInativar = e.target.closest('[data-inativar]');
  if (btnEditar) {
    const id = Number(btnEditar.dataset.editar);
    const prof = (await sb.from('professores').select('*').eq('id', id).single()).data;
    abrirModal(prof);
  } else if (btnInativar) {
    const id = Number(btnInativar.dataset.inativar);
    // RN14: nao inativar professor com turma ativa; avisar sobre matriculas ativas.
    const { data: turmas } = await sb.from('turmas').select('id, nome, status').eq('professor_id', id).eq('status', 'ativa');
    if (turmas && turmas.length) {
      toast('Este professor tem ' + turmas.length + ' turma(s) ativa(s). Encerre ou transfira as turmas antes de inativar.', 'erro');
      return;
    }
    const { data: mats } = await sb.from('matriculas').select('id').eq('professor_id', id).eq('status', 'ativa');
    const qtdMats = (mats || []).length;
    const msg = qtdMats
      ? 'Inativar este professor? Ele ainda tem ' + qtdMats + ' matricula(s) ativa(s) que continuam vinculadas.'
      : 'Inativar este professor?';
    if (!confirm(msg)) return;
    const { error } = await sb.from('professores').update({ ativo: false }).eq('id', id);
    if (error) toast(erroAmigo(error), 'erro');
    else { toast('Professor inativado.'); carregar(); }
  }
});

if (!me || me.perfil !== 'admin') {
  document.getElementById('novo').hidden = true;
}

carregar();
popularInstrumentos(sb);