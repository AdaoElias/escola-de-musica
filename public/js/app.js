import { guard, logout, perfil } from './auth.js';

const sb = await guard();
if (!sb) throw new Error('redirecionado');

const me = await perfil(sb);
const admin = me && me.perfil === 'admin';
document.getElementById('nome-user').textContent = (me && me.nome) || 'usuário';

document.getElementById('sair').addEventListener('click', logout);
for (const el of document.querySelectorAll('[data-futuro]')) {
  el.addEventListener('click', (e) => e.preventDefault());
}

const hoje = new Date();
const iso = hoje.toISOString().slice(0, 10);
const primeiroDoMes = iso.slice(0, 8) + '01';

function dinheiro(v) {
  return 'R$ ' + Number(v || 0).toLocaleString('pt-BR', { minimumFractionDigits: 2 });
}
function txt(id) {
  return document.getElementById(id);
}

const rMatriculas = sb.from('matriculas').select('tipo', { count: 'exact' }).eq('status', 'ativa');

const [
  rAlunosAtivos, rAlunosInativos, rProfessores, rTurmasAtivas,
  rTrancadas, rAulasMes, rAulasRecentes, rAlunosRecentes,
  rTurmas, rCm,
] = await Promise.all([
  sb.from('alunos').select('id', { count: 'exact', head: true }).eq('ativo', true),
  sb.from('alunos').select('id', { count: 'exact', head: true }).eq('ativo', false),
  sb.from('professores').select('id', { count: 'exact', head: true }).eq('ativo', true),
  sb.from('turmas').select('id', { count: 'exact', head: true }).eq('status', 'ativa'),
  sb.from('matriculas').select('id', { count: 'exact', head: true }).in('status', ['trancada', 'concluida']),
  sb.from('conteudos_ministrados').select('id', { count: 'exact', head: true }).gte('data_aula', primeiroDoMes),
  sb.from('conteudos_ministrados').select('data_aula, titulo, turma:turmas(nome), matricula:matriculas(aluno:alunos(nome))').order('data_aula', { ascending: false }).limit(5),
  sb.from('alunos').select('nome, criado_em').eq('ativo', true).order('criado_em', { ascending: false }).limit(5),
  sb.from('turmas').select('id, nome').eq('status', 'ativa'),
  sb.from('conteudos_ministrados').select('turma_id, grade_id'),
]);
const rMat = await rMatriculas;

const matAtivas = rMat.data || [];
const porTurma = matAtivas.filter((m) => m.tipo === 'turma').length;
const porIndividual = matAtivas.length - porTurma;

const cmRows = (rCm.data || []).filter((c) => c.turma_id);
const turmaIdsComAula = new Set(cmRows.map((c) => String(c.turma_id)));

txt('resumo-dia').textContent =
  new Date().toLocaleDateString('pt-BR', { weekday: 'long', day: 'numeric', month: 'long' }) +
  ' · ' + (rAulasMes.count || 0) + ' aula(s) neste mês';

const kpis = txt('kpis');

function cardKpi(classe, label, value, foot, href) {
  const a = document.createElement('a');
  a.className = 'kpi ' + classe;
  a.href = href || '#';
  a.addEventListener('click', (e) => { if (!href) e.preventDefault(); });
  a.innerHTML = `
    <div class="kpi-top"><span class="kpi-label">${label}</span></div>
    <div class="kpi-value">${value}</div>
    ${foot ? '<div class="kpi-foot">' + foot + '</div>' : ''}`;
  kpis.appendChild(a);
}

cardKpi('', 'Alunos ativos', rAlunosAtivos.count || 0,
  (rAlunosInativos.count ? rAlunosInativos.count + ' inativo(s)' : 'nenhum inativo'), '/alunos.html');
cardKpi('k-ok', 'Professores ativos', rProfessores.count || 0, null, '/professores.html');
cardKpi('k-warn', 'Turmas ativas', rTurmasAtivas.count || 0,
  'de ' + (rTurmas.data || []).length + ' no total', '/turmas.html');
cardKpi('k-ok', 'Matrículas ativas', matAtivas.length,
  porTurma + ' em turma · ' + porIndividual + ' individual', '/matriculas.html');

let rFinResumo = null, rInad = null;

if (admin) {
  [rFinResumo, rInad] = await Promise.all([
    sb.from('vw_financeiro_resumo').select('*').gte('competencia', primeiroDoMes).order('competencia', { ascending: false }).limit(1),
    sb.from('vw_inadimplentes').select('*').order('dias_atraso', { ascending: false }).limit(5),
  ]);
  const resumo = (rFinResumo.data || [])[0] || {};
  cardKpi('k-warn', 'A receber no mês', dinheiro(resumo.a_receber),
    'inclui atrasado: ' + dinheiro(resumo.inadimplente), null);
  cardKpi('k-err', 'Inadimplentes', (rInad.data || []).length,
    rInad.error ? 'financeiro indisponível' : 'em atraso', null);
}

const alerts = txt('alerts');

function alerta(tipo, titulo, texto, href) {
  const d = document.createElement('div');
  d.className = 'alert ' + (tipo || 'info');
  d.innerHTML = `
    <div>
      <span class="alert-title">${titulo}</span>
      <p>${texto}</p>
    </div>
    ${href ? '<a href="' + href + '">Ver mais</a>' : ''}`;
  alerts.appendChild(d);
}

const turmasLista = rTurmas.data || [];
const semAula = turmasLista.filter((t) => !turmaIdsComAula.has(String(t.id)));
semAula.slice(0, 3).forEach((t) => {
  alerta('info', 'Turma sem aulas ainda',
    '«' + t.nome + '» ainda não recebeu nenhum lançamento.', '/aulas.html');
});
if (semAula.length > 3) {
  alerta('info', 'E mais ' + (semAula.length - 3) + ' turma(s)',
    'Consultem a lista completa de turmas.', '/turmas.html');
}

const cmPorTurma = {};
for (const c of cmRows) {
  (cmPorTurma[c.turma_id] = cmPorTurma[c.turma_id] || []).push(c);
}
const semGrade = turmasLista.filter((t) => {
  const rows = cmPorTurma[Number(t.id)] || [];
  return rows.length > 0 && !rows.some((r) => r.grade_id != null);
});
semGrade.slice(0, 3).forEach((t) => {
  alerta('warning', 'Aulas sem item da grade',
    '«' + t.nome + '» lançou aulas mas nenhuma referenciou a grade padrão.', '/aulas.html');
});

const foraAtiva = rTrancadas.count || 0;
if (foraAtiva > 0) {
  alerta('warning', 'Matrículas fora de atividade',
    foraAtiva + ' matrícula(s) trancada(s) ou concluída(s).', '/matriculas.html');
}
if (rAlunosInativos.count) {
  alerta('info', 'Alunos inativos',
    rAlunosInativos.count + ' aluno(s) marcado(s) como inativo(s).', '/alunos.html');
}

if (admin && rInad && (rInad.data || []).length) {
  (rInad.data || []).slice(0, 4).forEach((f) => {
    alerta('danger', f.aluno,
      dinheiro(f.valor) + ' (' + f.descricao + ') venceu em ' + f.vencimento +
      ' — ' + f.dias_atraso + ' dia(s).', null);
  });
}

if (alerts.children.length === 0) {
  alerta('ok', 'Tudo em dia',
    'Nada precisa de atenção agora. Aproveite o restante do comando!', null);
}

const q = txt('qactions');
function acao(texto, href, destaque) {
  const a = document.createElement('a');
  a.className = 'btn small' + (destaque ? '' : ' ghost');
  a.href = href;
  a.textContent = texto;
  q.appendChild(a);
}
if (admin) {
  acao('+ Novo aluno', '/alunos.html', true);
  acao('+ Nova turma', '/turmas.html', true);
  acao('+ Nova matrícula', '/matriculas.html', true);
}
acao('+ Lançar aula', '/aulas.html', admin);
acao('Grade de conteúdos', '/grade.html', false);

const ulAlunos = txt('recentes-alunos');
if (!(rAlunosRecentes.data || []).length) {
  ulAlunos.innerHTML = '<li><span>Nenhum aluno cadastrado ainda.</span></li>';
} else {
  for (const a of rAlunosRecentes.data) {
    const li = document.createElement('li');
    li.innerHTML = '<strong>' + a.nome + '</strong><span>' + (a.criado_em || '').slice(0, 10) + '</span>';
    ulAlunos.appendChild(li);
  }
}

const ulAulas = txt('recentes-aulas');
if (!(rAulasRecentes.data || []).length) {
  ulAulas.innerHTML = '<li><span>Nenhuma aula lançada ainda.</span></li>';
} else {
  for (const a of rAulasRecentes.data) {
    const local = a.turma ? a.turma.nome : (a.matricula && a.matricula.aluno ? a.matricula.aluno.nome : '—');
    const li = document.createElement('li');
    li.innerHTML = '<strong>' + (a.titulo || local || 'Aula') + '</strong><span>' + a.data_aula + '</span>';
    ulAulas.appendChild(li);
  }
}