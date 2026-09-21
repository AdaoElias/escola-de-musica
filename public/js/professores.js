import { guard, logout, perfil } from './auth.js';

const sb = await guard();
if (!sb) throw new Error('redirecionado');

const tbody = document.getElementById('tbody');
const modal = document.getElementById('modal');
const form = document.getElementById('form');
const erro = document.getElementById('erro');
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
      <td>${p.instrumento || '—'}</td>
      <td>${p.email || '—'}</td>
      <td>${p.telefone || '—'}</td>
      <td>${p.ativo ? 'Ativo' : 'Inativo'}</td>
      <td class="acoes">
        ${p.ativo ? '<button class="mini" data-editar="' + p.id + '">Editar</button>' : ''}
        ${p.ativo ? '<button class="mini danger" data-inativar="' + p.id + '">Inativar</button>' : ''}
      </td>`;
    tbody.appendChild(tr);
  }
}

function mostrarErroTabela(msg) {
  const tr = document.createElement('tr');
  tr.innerHTML = '<td colspan="6" class="error">Erro ao carregar: ' + msg + '</td>';
  tbody.appendChild(tr);
}

function abrirModal(prof = null) {
  erro.textContent = '';
  editando = prof;
  document.getElementById('titulo-modal').textContent = prof ? 'Editar professor' : 'Novo professor';
  document.getElementById('id').value = prof ? prof.id : '';
  document.getElementById('nome').value = prof ? prof.nome : '';
  document.getElementById('instrumento').value = prof ? (prof.instrumento || '') : '';
  document.getElementById('email').value = prof ? (prof.email || '') : '';
  document.getElementById('telefone').value = prof ? (prof.telefone || '') : '';
  document.getElementById('formacao').value = prof ? (prof.formacao || '') : '';
  document.getElementById('ativo').checked = prof ? prof.ativo : true;
  modal.showModal();
}

document.getElementById('novo').addEventListener('click', () => abrirModal());
document.getElementById('cancelar').addEventListener('click', () => modal.close());

form.addEventListener('submit', async (e) => {
  e.preventDefault();
  erro.textContent = '';
  const dados = {
    nome: document.getElementById('nome').value.trim(),
    instrumento: document.getElementById('instrumento').value.trim() || null,
    email: document.getElementById('email').value.trim() || null,
    telefone: document.getElementById('telefone').value.trim() || null,
    formacao: document.getElementById('formacao').value.trim() || null,
    ativo: document.getElementById('ativo').checked,
  };
  if (!dados.nome) return;

  const { error } = editando
    ? await sb.from('professores').update(dados).eq('id', editando.id)
    : await sb.from('professores').insert(dados);

  if (error) {
    erro.textContent = 'Erro: ' + error.message;
    return;
  }
  modal.close();
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