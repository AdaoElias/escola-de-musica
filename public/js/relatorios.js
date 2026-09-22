import { guard, logout, perfil } from './auth.js';
import { linha, barras } from './graficos.js';
import { baixarCsv } from './csv.js';

const sb = await guard();
if (!sb) throw new Error('redirecionado');

const me = await perfil(sb);
const admin = me && me.perfil === 'admin';

document.getElementById('sair').addEventListener('click', logout);

const selTurma = document.getElementById('sel-turma');
const selAluno = document.getElementById('sel-aluno');
let turmaPts = [];
let alunoPts = [];
let finRows = [];

function dinheiroCurto(v) {
  return 'R$ ' + Number(v || 0).toLocaleString('pt-BR', { maximumFractionDigits: 0 });
}
function dinheiroCheio(v) {
  return 'R$ ' + Number(v || 0).toLocaleString('pt-BR', { minimumFractionDigits: 2 });
}
function mesLabel(ts) {
  return (ts || '').slice(0, 7).replace('-', '/');
}

async function carregarTurmas() {
  const { data } = await sb.from('turmas').select('id, nome').eq('status', 'ativa').order('nome');
  selTurma.innerHTML = '';
  const lista = data || [];
  for (const t of lista) {
    const o = document.createElement('option');
    o.value = t.id;
    o.textContent = t.nome;
    selTurma.appendChild(o);
  }
  if (lista.length) {
    selTurma.disabled = false;
    await carregarDesempenhoTurma(lista[0].id);
  } else {
    selTurma.disabled = true;
    document.getElementById('graf-turma').innerHTML = '<p class="graf-vazio">Nenhuma turma ativa.</p>';
  }
}

async function carregarDesempenhoTurma(id) {
  const g = document.getElementById('graf-turma');
  g.innerHTML = '<p class="sub">Carregando…</p>';
  const { data } = await sb.from('vw_desempenho_turma')
    .select('*')
    .eq('turma_id', id)
    .order('data_aula', { ascending: true });
  const pts = (data || []).map((r) => ({
    x: (r.data_aula || '').slice(0, 7).replace('-', '/'),
    y: Number(r.evolucao_media || 0),
  }));
  turmaPts = pts;
  linha(g, pts, { cor: 'var(--primaria)', fmt: (v) => Math.round(v) + '%' });
}

async function carregarAlunos() {
  const { data } = await sb.from('alunos').select('id, nome').eq('ativo', true).order('nome');
  selAluno.innerHTML = '';
  const lista = data || [];
  for (const a of lista) {
    const o = document.createElement('option');
    o.value = a.id;
    o.textContent = a.nome;
    selAluno.appendChild(o);
  }
  if (lista.length) {
    selAluno.disabled = false;
    await carregarDesempenhoAluno(lista[0].id);
  } else {
    selAluno.disabled = true;
    document.getElementById('graf-aluno').innerHTML = '<p class="graf-vazio">Nenhum aluno ativo.</p>';
  }
}

async function carregarDesempenhoAluno(id) {
  const g = document.getElementById('graf-aluno');
  g.innerHTML = '<p class="sub">Carregando…</p>';
  const { data } = await sb.from('vw_desempenho_aluno')
    .select('*')
    .eq('aluno_id', id)
    .order('data', { ascending: true });
  const pts = (data || []).map((r) => ({
    x: (r.data || '').slice(0, 10),
    y: Number(r.desempenho || 0),
  }));
  alunoPts = pts;
  linha(g, pts, { cor: 'var(--ok)', fmt: (v) => Math.round(v) + '%' });
}

async function carregarFinanceiro() {
  if (!admin) {
    document.getElementById('sec-fin').hidden = true;
    return;
  }
  const g = document.getElementById('graf-fin');
  g.innerHTML = '<p class="sub">Carregando…</p>';
  const { data, error } = await sb.from('vw_financeiro_resumo')
    .select('*')
    .order('competencia', { ascending: true });
  if (error) {
    g.innerHTML = '<p class="graf-vazio">Financeiro indisponível: ' + error.message + '</p>';
    return;
  }
  const rows = (data || []).slice(-12);
  finRows = rows;
  barras(g, {
    categorias: rows.map((r) => mesLabel(r.competencia)),
    series: [
      { nome: 'A receber', cor: 'var(--warning)', valores: rows.map((r) => r.a_receber) },
      { nome: 'Recebido', cor: 'var(--ok)', valores: rows.map((r) => r.recebido) },
    ],
    fmt: dinheiroCurto,
  });
}

function exportarTurma() {
  const nome = selTurma.options[selTurma.selectedIndex]?.textContent || 'turma';
  baixarCsv('desempenho_turma_' + nome.replace(/\s+/g, '_'),
    ['Competência', 'Evolução média (%)'],
    turmaPts.map((p) => [p.x, p.y]));
}
function exportarAluno() {
  const nome = selAluno.options[selAluno.selectedIndex]?.textContent || 'aluno';
  baixarCsv('desempenho_aluno_' + nome.replace(/\s+/g, '_'),
    ['Data', 'Desempenho (%)'],
    alunoPts.map((p) => [p.x, p.y]));
}
function exportarFin() {
  baixarCsv('financeiro_por_competencia',
    ['Competência', 'A receber', 'Recebido', 'Inadimplente'],
    finRows.map((r) => [mesLabel(r.competencia), dinheiroCheio(r.a_receber), dinheiroCheio(r.recebido), dinheiroCheio(r.inadimplente)]));
}

document.getElementById('exp-turma').addEventListener('click', exportarTurma);
document.getElementById('exp-aluno').addEventListener('click', exportarAluno);
document.getElementById('exp-fin').addEventListener('click', exportarFin);

selTurma.addEventListener('change', () => carregarDesempenhoTurma(Number(selTurma.value)));
selAluno.addEventListener('change', () => carregarDesempenhoAluno(Number(selAluno.value)));

await Promise.all([carregarTurmas(), carregarAlunos(), carregarFinanceiro()]);