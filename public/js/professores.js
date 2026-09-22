import { guard, logout, perfil } from './auth.js';
import { toast, ligaFecharModais, buscarCep, ligaMascaraTelefone, emailValido, ligaMascaraCpf, formatarCpf, formatarDataBr } from './ui.js';
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
      <td>${p.ativo ? '<span class="badge b-ok">Ativo</span>' : '<span class="badge b-mut">Inativo</span>'}</td>
      <td class="acoes">
        ${p.ativo ? '<button class="mini" data-editar="' + p.id + '">Editar</button>' : ''}
        ${p.ativo ? '<button class="mini danger" data-inativar="' + p.id + '">Inativar</button>' : ''}
      </td>`;
    tbody.appendChild(tr);
  }
  if (!data.length) {
    tbody.innerHTML = '<tr><td colspan="9" class="empty">Nenhum professor cadastrado ainda.</td></tr>';
  }
}

function mostrarErroTabela(msg) {
  const tr = document.createElement('tr');
  tr.innerHTML = '<td colspan="9" class="error">Erro ao carregar: ' + msg + '</td>';
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
  modal.showModal();
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

  const { error } = editando
    ? await sb.from('professores').update(dados).eq('id', editando.id)
    : await sb.from('professores').insert(dados);

  if (error) {
    erro.textContent = 'Erro: ' + error.message;
    salvarBtn.disabled = false;
    return;
  }
  modal.close();
  toast(editando ? 'Professor atualizado.' : 'Professor cadastrado.');
carregar();
popularInstrumentos(sb);
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
    const ok = confirm('Inativar este professor?');
    if (!ok) return;
    const { error } = await sb.from('professores').update({ ativo: false }).eq('id', id);
    if (!error) carregar();
  }
});

if (!me || me.perfil !== 'admin') {
  document.getElementById('novo').hidden = true;
}

carregar();