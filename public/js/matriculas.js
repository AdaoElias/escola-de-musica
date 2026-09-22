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
let turmas = [], professores = [];

const me = await perfil(sb);
const admin = me && me.perfil === 'admin';

const campoTurma = document.getElementById('campo-turma');
const campoProfessor = document.getElementById('campo-professor');
const campoValorMensal = document.getElementById('campo-valor-mensal');
const campoValorAula = document.getElementById('campo-valor-aula');

document.getElementById('sair').addEventListener('click', logout);
for (const el of document.querySelectorAll('[data-futuro]')) {
  el.addEventListener('click', (e) => e.preventDefault());
}

async function carregarAlunos() {
  const { data } = await sb.from('alunos').select('id, nome').eq('ativo', true).order('nome');
  const sel = document.getElementById('aluno_id');
  sel.innerHTML = '';
  for (const a of data || []) {
    const opt = document.createElement('option');
    opt.value = a.id;
    opt.textContent = a.nome;
    sel.appendChild(opt);
  }
}

async function carregarTurmas() {
  const { data } = await sb.from('turmas').select('id, nome, valor_mensal').eq('status', 'ativa').order('nome');
  turmas = data || [];
  const sel = document.getElementById('turma_id');
  sel.innerHTML = '';
  for (const t of turmas) {
    const opt = document.createElement('option');
    opt.value = t.id;
    opt.textContent = t.nome + ' (R$ ' + Number(t.valor_mensal).toFixed(2) + ')';
    sel.appendChild(opt);
  }
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

function atualizarCampos(tipo, pagamento) {
  const individual = tipo === 'individual';
  campoTurma.style.display = individual ? 'none' : 'flex';
  campoProfessor.style.display = individual ? 'flex' : 'none';
  document.getElementById('tipo_pagamento').options[1].disabled = !individual;
  if (!individual) document.getElementById('tipo_pagamento').value = 'mensal';
  campoValorMensal.style.display = pagamento === 'mensal' ? 'flex' : 'none';
  campoValorAula.style.display = pagamento === 'avulsa' ? 'flex' : 'none';
}

document.getElementById('tipo').addEventListener('change', (e) => {
  const tipo = e.target.value;
  if (tipo === 'individual') {
    document.getElementById('valor_aula').value = document.getElementById('valor_aula').value || '';
  }
  atualizarCampos(tipo, document.getElementById('tipo_pagamento').value);
});

document.getElementById('tipo_pagamento').addEventListener('change', (e) => {
  atualizarCampos(document.getElementById('tipo').value, e.target.value);
});

document.getElementById('turma_id').addEventListener('change', (e) => {
  const t = turmas.find((x) => x.id === Number(e.target.value));
  if (t) document.getElementById('valor_mensal').value = t.valor_mensal;
});

async function carregar() {
  const { data, error } = await sb.from('matriculas')
    .select('*, aluno:alunos(nome), turma:turmas(nome), professor:professores(nome)')
    .order('data_inicio', { ascending: false });
  if (error) return mostrarErroTabela(error.message);
  tbody.innerHTML = '';
  for (const m of data) {
    const valor = m.tipo_pagamento === 'avulsa'
      ? 'R$ ' + Number(m.valor_aula).toFixed(2) + '/aula'
      : 'R$ ' + Number(m.valor_mensal).toFixed(2) + '/mês';
    const vinculo = m.tipo === 'turma'
      ? (m.turma ? m.turma.nome : '—')
      : (m.professor ? m.professor.nome : '—');
    const statusBadge = m.status === 'ativa'
      ? '<span class="badge b-ok">Ativa</span>'
      : (m.status === 'trancada' ? '<span class="badge b-warn">Trancada</span>' : '<span class="badge b-info">Concluída</span>');
    const tr = document.createElement('tr');
    tr.innerHTML = `
      <td>${m.aluno ? m.aluno.nome : '—'}</td>
      <td>${m.tipo === 'turma' ? 'Turma' : 'Individual'}</td>
      <td>${vinculo}</td>
      <td>${m.tipo_pagamento === 'avulsa' ? 'Avulsa' : 'Mensal'}</td>
      <td>${valor}</td>
      <td>${statusBadge}</td>
      <td>${m.data_inicio}</td>
      <td class="acoes">
        <button class="mini" data-editar="${m.id}">Editar</button>
      </td>`;
    tbody.appendChild(tr);
  }
  if (!data.length) tbody.innerHTML = '<tr><td colspan="8" class="empty">Nenhuma matrícula cadastrada ainda.</td></tr>';
}

function mostrarErroTabela(msg) {
  const tr = document.createElement('tr');
  tr.innerHTML = '<td colspan="8" class="error">Erro ao carregar: ' + msg + '</td>';
  tbody.appendChild(tr);
}

function abrirModal(m = null) {
  erro.textContent = '';
  salvarBtn.disabled = false;
  editando = m;
  document.getElementById('titulo-modal').textContent = m ? 'Editar matrícula' : 'Nova matrícula';
  document.getElementById('id').value = m ? m.id : '';
  document.getElementById('aluno_id').value = m ? m.aluno_id : (document.getElementById('aluno_id').options[0]?.value || '');
  document.getElementById('tipo').value = m ? m.tipo : 'turma';
  document.getElementById('tipo_pagamento').value = m ? m.tipo_pagamento : 'mensal';
  document.getElementById('turma_id').value = m ? (m.turma_id || document.getElementById('turma_id').options[0]?.value || '') : (document.getElementById('turma_id').options[0]?.value || '');
  document.getElementById('professor_id').value = m ? (m.professor_id || professores[0]?.id || '') : (professores[0]?.id || '');
  document.getElementById('valor_mensal').value = m ? m.valor_mensal : '';
  document.getElementById('valor_aula').value = m ? m.valor_aula : '';
  document.getElementById('status_matricula').value = m ? m.status : 'ativa';
  document.getElementById('data_inicio').value = m ? m.data_inicio : new Date().toISOString().slice(0, 10);
  atualizarCampos(document.getElementById('tipo').value, document.getElementById('tipo_pagamento').value);
  modal.showModal();
}

document.getElementById('novo').addEventListener('click', () => abrirModal());
document.getElementById('cancelar').addEventListener('click', () => modal.close());
ligaFecharModais(modal);

form.addEventListener('submit', async (e) => {
  e.preventDefault();
  erro.textContent = '';
  salvarBtn.disabled = true;
  const tipo = document.getElementById('tipo').value;
  const pagamento = document.getElementById('tipo_pagamento').value;
  const dados = {
    aluno_id: Number(document.getElementById('aluno_id').value),
    tipo,
    turma_id: tipo === 'turma' ? Number(document.getElementById('turma_id').value) : null,
    professor_id: tipo === 'individual' ? Number(document.getElementById('professor_id').value) : null,
    tipo_pagamento: pagamento,
    valor_mensal: pagamento === 'mensal' ? Number(document.getElementById('valor_mensal').value || 0) : 0,
    valor_aula: pagamento === 'avulsa' ? Number(document.getElementById('valor_aula').value || 0) : 0,
    status: document.getElementById('status_matricula').value,
    data_inicio: document.getElementById('data_inicio').value || new Date().toISOString().slice(0, 10),
  };
  if (!dados.aluno_id) {
    salvarBtn.disabled = false;
    return;
  }

  const { error } = editando
    ? await sb.from('matriculas').update(dados).eq('id', editando.id)
    : await sb.from('matriculas').insert(dados);

  if (error) {
    erro.textContent = 'Erro: ' + error.message;
    salvarBtn.disabled = false;
    return;
  }
  modal.close();
  toast(editando ? 'Matrícula atualizada.' : 'Matrícula criada.');
  carregar();
});

tbody.addEventListener('click', async (e) => {
  const btnEditar = e.target.closest('[data-editar]');
  if (btnEditar) {
    const id = Number(btnEditar.dataset.editar);
    const { data } = await sb.from('matriculas').select('*').eq('id', id).single();
    abrirModal(data);
  }
});

if (!admin) document.getElementById('novo').hidden = true;
await Promise.all([carregarAlunos(), carregarTurmas(), carregarProfessores()]);
carregar();