import { guard, logout, perfil } from './auth.js';

const sb = await guard();
if (!sb) throw new Error('redirecionado');

const tbody = document.getElementById('tbody');
const modal = document.getElementById('modal');
const form = document.getElementById('form');
const erro = document.getElementById('erro');
let editando = null;

const me = await perfil(sb);
const admin = me && me.perfil === 'admin';

document.getElementById('sair').addEventListener('click', logout);
for (const el of document.querySelectorAll('[data-futuro]')) {
  el.addEventListener('click', (e) => e.preventDefault());
}

async function carregar() {
  const { data, error } = await sb.from('alunos').select('*').order('nome');
  if (error) return mostrarErroTabela(error.message);
  tbody.innerHTML = '';
  for (const a of data) {
    const tr = document.createElement('tr');
    tr.innerHTML = `
      <td>${a.nome}</td>
      <td>${a.telefone || '—'}</td>
      <td>${a.email || '—'}</td>
      <td>${a.ativo ? 'Ativo' : 'Inativo'}</td>
      <td class="acoes">
        ${a.ativo ? '<button class="mini" data-editar="' + a.id + '">Editar</button>' : ''}
        ${a.ativo ? '<button class="mini danger" data-inativar="' + a.id + '">Inativar</button>' : ''}
      </td>`;
    tbody.appendChild(tr);
  }
}

function mostrarErroTabela(msg) {
  const tr = document.createElement('tr');
  tr.innerHTML = '<td colspan="5" class="error">Erro ao carregar: ' + msg + '</td>';
  tbody.appendChild(tr);
}

function abrirModal(aluno = null) {
  erro.textContent = '';
  editando = aluno;
  document.getElementById('titulo-modal').textContent = aluno ? 'Editar aluno' : 'Novo aluno';
  document.getElementById('id').value = aluno ? aluno.id : '';
  document.getElementById('nome').value = aluno ? aluno.nome : '';
  document.getElementById('telefone').value = aluno ? (aluno.telefone || '') : '';
  document.getElementById('email').value = aluno ? (aluno.email || '') : '';
  document.getElementById('observacao').value = aluno ? (aluno.observacao || '') : '';
  document.getElementById('ativo').checked = aluno ? aluno.ativo : true;
  modal.showModal();
}

document.getElementById('novo').addEventListener('click', () => abrirModal());
document.getElementById('cancelar').addEventListener('click', () => modal.close());

form.addEventListener('submit', async (e) => {
  e.preventDefault();
  erro.textContent = '';
  const dados = {
    nome: document.getElementById('nome').value.trim(),
    telefone: document.getElementById('telefone').value.trim() || null,
    email: document.getElementById('email').value.trim() || null,
    observacao: document.getElementById('observacao').value.trim() || null,
    ativo: document.getElementById('ativo').checked,
  };
  if (!dados.nome) return;

  const { error } = editando
    ? await sb.from('alunos').update(dados).eq('id', editando.id)
    : await sb.from('alunos').insert(dados);

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
    const { data } = await sb.from('alunos').select('*').eq('id', id).single();
    abrirModal(data);
  } else if (btnInativar) {
    const id = Number(btnInativar.dataset.inativar);
    if (!confirm('Inativar este aluno?')) return;
    const { error } = await sb.from('alunos').update({ ativo: false }).eq('id', id);
    if (!error) carregar();
  }
});

if (!admin) document.getElementById('novo').hidden = true;
carregar();