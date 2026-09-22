import { guard, logout, perfil } from './auth.js';
import { toast, formatarCpf } from './ui.js';

const sb = await guard();
if (!sb) throw new Error('redirecionado');

const me = await perfil(sb);
const admin = me && me.perfil === 'admin';
const params = new URLSearchParams(location.search);
const matriculaId = Number(params.get('matricula'));
const tipo = params.get('tipo') === 'carne' ? 'carne' : 'recibo';

document.getElementById('sair')?.addEventListener('click', logout);
document.getElementById('imprimir').addEventListener('click', () => window.print());

const DIAS = {
  segunda: 'Segunda-feira', terca: 'Terça-feira', quarta: 'Quarta-feira',
  quinta: 'Quinta-feira', sexta: 'Sexta-feira', sabado: 'Sábado',
};

function esc(s) {
  return String(s).replace(/[&<>"']/g, (c) => ({
    '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;',
  }[c]));
}
function dinheiro(v) {
  return 'R$ ' + Number(v || 0).toLocaleString('pt-BR', { minimumFractionDigits: 2 });
}
function dataBr(d) {
  return d ? d.slice(0, 10).split('-').reverse().join('/') : '—';
}
function mesBr(ts) {
  const s = (ts || '').slice(0, 7);
  if (!s) return '';
  const [a, m] = s.split('-');
  const meses = ['jan', 'fev', 'mar', 'abr', 'mai', 'jun', 'jul', 'ago', 'set', 'out', 'nov', 'dez'];
  return meses[Number(m) - 1] + '/' + a;
}
function menorDeIdade(nascimento) {
  if (!nascimento) return false;
  const n = new Date(nascimento + 'T00:00:00');
  const hoje = new Date();
  let idade = hoje.getFullYear() - n.getFullYear();
  const m = hoje.getMonth() - n.getMonth();
  if (m < 0 || (m === 0 && hoje.getDate() < n.getDate())) idade--;
  return idade < 18;
}
function condicao(m) {
  if (m.tipo_pagamento === 'parcelado') {
    const qtd = Number(m.parcelas) || 1;
    return `Valor do curso: ${dinheiro(m.valor_total)} em ${qtd}x de ${dinheiro(Number(m.valor_total) / qtd)}`;
  }
  if (m.tipo_pagamento === 'avulsa') return `Aula avulsa: ${dinheiro(m.valor_aula)} por aula`;
  return `Mensalidade: ${dinheiro(m.valor_mensal)} por mês`;
}

async function carregar() {
  const doc = document.getElementById('doc');
  if (!matriculaId) {
    doc.innerHTML = '<p class="empty">Matrícula inválida.</p>';
    return;
  }
  const { data: m, error } = await sb.from('matriculas')
    .select('*, aluno:alunos(*), turma:turmas(*), professor:professores(nome)')
    .eq('id', matriculaId)
    .single();
  if (error) {
    doc.innerHTML = '<p class="error">Erro ao carregar: ' + error.message + '</p>';
    return;
  }
  if (tipo === 'carne' && !admin) {
    doc.innerHTML = '<p class="empty">O carnê financeiro é exclusivo do administrador (RF30).</p>';
    return;
  }

  const aluno = m.aluno;
  const menor = menorDeIdade(aluno ? aluno.nascimento : null);
  const curso = m.turma ? m.turma.nome : 'Aluno VIP';
  const diaHora = m.turma
    ? (m.turma.dia_semana ? (DIAS[m.turma.dia_semana] || m.turma.dia_semana) : '—') + ' às ' + (m.turma.horario ? m.turma.horario.slice(0, 5) : '—')
    : (m.dia_semana ? (DIAS[m.dia_semana] || m.dia_semana) : '—') + ' às ' + (m.horario ? m.horario.slice(0, 5) : '—');

  const linhas = [
    ['Matrícula nº', String(m.id)],
    ['Aluno(a)', aluno ? aluno.nome : '—'],
    menor && aluno.responsavel_nome ? ['Responsável', aluno.responsavel_nome + (aluno.responsavel_cpf ? ' · CPF ' + formatarCpf(aluno.responsavel_cpf) : '')] : null,
    ['Curso / Turma', curso],
    ['Professor(a)', m.professor ? m.professor.nome : '—'],
    ['Dia / Horário', diaHora],
    ['Data de início', dataBr(m.data_inicio)],
    ['Taxa de matrícula', dinheiro(m.valor_matricula) + ' (paga no ato, ' + (m.matricula_forma_pagamento || 'pix') + ')'],
    ['Condição de pagamento', condicao(m)],
  ].filter(Boolean);

  const tabela = linhas.map(([k, v]) =>
    '<tr><td class="k">' + k + '</td><td class="v">' + esc(v) + '</td></tr>').join('');

  if (tipo === 'carne') {
    const { data, error: e2 } = await sb.from('financeiro')
      .select('*')
      .eq('matricula_id', matriculaId)
      .eq('tipo', 'mensalidade')
      .order('competencia', { ascending: true });
    if (e2) {
      doc.innerHTML = '<p class="error">Erro ao carregar parcelas: ' + e2.message + '</p>';
      return;
    }
    const parcela = data || [];
    doc.innerHTML = carnesHtml(parcela, m, aluno, curso);
    return;
  }

  doc.innerHTML =
    via('RECIBO DE MATRÍCULA', tabela, '1ª VIA — ALUNO / RESPONSÁVEL') +
    '<div class="corte no-print">— — — — — RECORTE AQUI — — — — —</div>' +
    via('RECIBO DE MATRÍCULA', tabela, '2ª VIA — ESCOLA');
}

function via(titulo, tabela, viaNome) {
  return `
  <section class="via">
    <header class="doc-head">
      <div class="doc-brand"><span class="doc-icon">♪</span><h1>Escola de Música</h1></div>
      <div class="doc-titulo">${titulo}<br><small>${viaNome}</small></div>
    </header>
    <table class="doc-ficha">
      ${tabela}
    </table>
    <footer class="doc-assin">
      <div><span>Assinatura do aluno / responsável</span></div>
      <div><span>Assinatura da escola</span></div>
    </footer>
  </section>`;
}

function canhotoHtml(parcela, idx, ctx) {
  const { m, aluno, curso } = ctx;
  const N = ctx.N;
  const alunoNome = aluno ? aluno.nome : '—';
  const responsavel = aluno && aluno.responsavel_nome ? aluno.responsavel_nome : null;
  const venc = dataBr(parcela.vencimento);
  const ref = mesBr(parcela.competencia);
  const valor = dinheiro(parcela.valor);
  const st = parcela.status === 'paga'
    ? '<span class="cn-st pago">PAGO ' + dataBr(parcela.data_pagamento) + '</span>'
    : (parcela.status === 'cancelada' ? '<span class="cn-st canc">CANCELADA</span>' : '<span class="cn-st pend">PENDENTE</span>');
  const ficha = [
    ['Aluno(a)', alunoNome],
    ['Curso / Turma', curso],
    ['Matrícula nº', String(m.id)],
    ['Vencimento', venc + (ref ? ' · Ref. ' + ref : '')],
    responsavel ? ['Responsável', responsavel] : null,
    ['Parcela', idx + ' de ' + N],
  ].filter(Boolean).map(([k, v]) =>
    '<div class="cn-f"><span>' + k + '</span><strong>' + esc(v) + '</strong></div>').join('');

  return `
  <div class="canhoto">
    <div class="cn-top">
      <span class="cn-brand">♪ Escola de Música</span>
      ${st}
    </div>
    <div class="cn-title">Carnê de pagamento — Parcela ${idx} de ${N}</div>
    <div class="cn-valor">${valor}</div>
    <div class="cn-ficha">${ficha}</div>
    <div class="cn-recebi">
      Recebemos de ${esc(alunoNome)} a importância de ${valor} referente à ${idx}ª parcela
      do curso de ${esc(curso)}${responsavel ? ' (responsável: ' + esc(responsavel) + ')' : ''}.
    </div>
    <div class="cn-ass">
      <span>Assinatura da escola</span>
      <span>Assinatura do aluno / responsável</span>
    </div>
  </div>`;
}

function carnesHtml(parcela, m, aluno, curso) {
  if (!parcela.length) {
    return '<p class="empty">Nenhuma parcela gerada — use "Carnê" na matrícula para gerar.</p>';
  }
  const N = parcela.length;
  const ctx = { m, aluno, curso, N };
  const linhas = parcela.map((p, i) => {
    const c = canhotoHtml(p, i + 1, ctx);
    return '<div class="carne-linha">' + c + '<div class="copia">' + c + '</div></div>';
  }).join('');
  return `<div class="carne"><p class="carne-intro">
    CARNÊ DE PAGAMENTO — ${esc(aluno ? aluno.nome : '')} · ${esc(curso)} · ${N} parcela(s).
    Recortar pelo tracejado e guardar os canhotos.
  </p>${linhas}</div>`;
}

carregar().then(() => {
  setTimeout(() => window.print(), 400);
}).catch(() => toast('Erro ao carregar documento.', 'erro'));