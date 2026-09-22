import { guard, logout, perfil } from './auth.js';
import { toast, ligaFecharModais } from './ui.js';

const sb = await guard();
if (!sb) throw new Error('redirecionado');

const tbody = document.getElementById('tbody');
const modal = document.getElementById('modal');
const form = document.getElementById('form');
const erro = document.getElementById('erro');
const salvarBtn = document.getElementById('btn-salvar');
let editando = null;
let professores = [];

const me = await perfil(sb);
const admin = me && me.perfil === 'admin';

document.getElementById('sair').addEventListener('click', logout);
for (const el of document.querySelectorAll('[data-futuro]')) {
  el.addEventListener('click', (e) => e.preventDefault());
}

async function carregarProfessores() {
  const { data } = await sb.from('professores').select('id, nome').eq('ativo', true).order('nome');
  professores = data || [];
  const sel = document.getElementById('professor_id');
  sel.innerHTML = '';
  for (const p of professores) {
    const opt = document.createElement('option');
    opt.value = p.id;
    opt.textContent = p.nome;
    sel.appendChild(opt);
  }
}

async function carregar() {
  const { data, error } = await sb.from('turmas').select('*, professor:professores(nome)').order('nome');
  if (error) return mostrarErroTabela(error.message);
  tbody.innerHTML = '';
  for (const t of data) {
    const hora = t.horario ? t.horario.slice(0, 5) : '—';
    const tr = document.createElement('tr');
    tr.innerHTML = `
      <td>${t.nome}</td>
      <td>${t.instrumento || '—'}</td>
      <td>${t.professor ? t.professor.nome : '—'}</td>
      <td>${t.dia_semana || '—'}</td>
      <td>${hora}</td>
      <td>R$ ${Number(t.valor_mensal).toFixed(2)}</td>
      <td>${t.status === 'ativa' ? '<span class="badge b-ok">Ativa</span>' : '<span class="badge b-mut">Encerrada</span>'}</td>
      <td class="acoes">
        <button class="mini" data-editar="${t.id}">Editar</button>
        ${t.status === 'ativa' ? '<button class="mini danger" data-encerrar="' + t.id + '">Encerrar</button>' : ''}
      </td>`;
    tbody.appendChild(tr);
  }
  if (!data.length) tbody.innerHTML = '<tr><td colspan="8" class="empty">Nenhuma turma cadastrada ainda.</td></tr>';
}

function mostrarErroTabela(msg) {
  const tr = document.createElement('tr');
  tr.innerHTML = '<td colspan="8" class="error">Erro ao carregar: ' + msg + '</td>';
  tbody.appendChild(tr);
}

function abrirModal(turma = null) {
  erro.textContent = '';
  salvarBtn.disabled = false;
  editando = turma;
  document.getElementById('titulo-modal').textContent = turma ? 'Editar turma' : 'Nova turma';
  document.getElementById('id').value = turma ? turma.id : '';
  document.getElementById('nome').value = turma ? turma.nome : '';
  document.getElementById('instrumento').value = turma ? (turma.instrumento || '') : '';
  document.getElementById('professor_id').value = turma ? turma.professor_id : (professores[0] ? professores[0].id : '');
  document.getElementById('dia_semana').value = turma ? (turma.dia_semana || 'Segunda') : 'Segunda';
  document.getElementById('horario').value = turma && turma.horario ? turma.horario.slice(0, 5) : '';
  document.getElementById('valor_mensal').value = turma ? turma.valor_mensal : '';
  document.getElementById('status').value = turma ? turma.status : 'ativa';
  modal.showModal();
}

document.getElementById('novo').addEventListener('click', () => abrirModal());
document.getElementById('cancelar').addEventListener('click', () => modal.close());
ligaFecharModais(modal);

form.addEventListener('submit', async (e) => {
  e.preventDefault();
  erro.textContent = '';
  salvarBtn.disabled = true;
  const horario = document.getElementById('horario').value;
  const dados = {
    nome: document.getElementById('nome').value.trim(),
    instrumento: document.getElementById('instrumento').value.trim() || null,
    professor_id: Number(document.getElementById('professor_id').value),
    dia_semana: document.getElementById('dia_semana').value,
    horario: horario ? horario + ':00' : null,
    valor_mensal: Number(document.getElementById('valor_mensal').value || 0),
    status: document.getElementById('status').value,
  };
  if (!dados.nome) {
    salvarBtn.disabled = false;
    return;
  }

  const { error } = editando
    ? await sb.from('turmas').update(dados).eq('id', editando.id)
    : await sb.from('turmas').insert(dados);

  if (error) {
    erro.textContent = 'Erro: ' + error.message;
    salvarBtn.disabled = false;
    return;
  }
  modal.close();
  toast(editando ? 'Turma atualizada.' : 'Turma criada.');
  carregar();
});

tbody.addEventListener('click', async (e) => {
  const btnEditar = e.target.closest('[data-editar]');
  const btnEncerrar = e.target.closest('[data-encerrar]');
  if (btnEditar) {
    const id = Number(btnEditar.dataset.editar);
    const { data } = await sb.from('turmas').select('*').eq('id', id).single();
    abrirModal(data);
  } else if (btnEncerrar) {
    const id = Number(btnEncerrar.dataset.encerrar);
    if (!confirm('Encerrar esta turma?')) return;
    const { error } = await sb.from('turmas').update({ status: 'encerrada' }).eq('id', id);
    if (!error) carregar();
  }
});

if (!admin) document.getElementById('novo').hidden = true;
await carregarProfessores();
carregar();