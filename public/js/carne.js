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

function dinheiro(v) {
  return 'R$ ' + Number(v || 0).toLocaleString('pt-BR', { minimumFractionDigits: 2 });
}
function dataBr(d) {
  return d ? d.slice(0, 10).split('-').reverse().join('/') : '—';
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

  let parcela = [];
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
    parcela = data || [];
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
    '<tr><td class="k">' + k + '</td><td class="v">' + v + '</td></tr>').join('');

  const titulo = tipo === 'carne' ? 'CARNÊ DE PAGAMENTO' : 'RECIBO DE MATRÍCULA';

  doc.innerHTML =
    via(titulo, aluno, tabela, '1ª VIA — ALUNO / RESPONSÁVEL', m, parcela, menor) +
    '<div class="corte no-print">— — — — — RECORTE AQUI — — — — —</div>' +
    via(titulo, aluno, tabela, '2ª VIA — ESCOLA', m, parcela, menor);
}

function via(titulo, aluno, tabela, viaNome, m, parcela, menor) {
  const parcelasHtml = tipo === 'carne'
    ? tabelaParcelas(parcela)
    : '';
  const pago = parcela.filter((p) => p.status === 'paga').length;
  return `
  <section class="via">
    <header class="doc-head">
      <div class="doc-brand"><span class="doc-icon">♪</span><h1>Escola de Música</h1></div>
      <div class="doc-titulo">${titulo}<br><small>${viaNome}</small></div>
    </header>
    <table class="doc-ficha">
      ${tabela}
    </table>
    ${tipo === 'carne' ? `
    <div class="doc-resumo">
      Total do curso: <strong>${dinheiro(Number(m.valor_total))}</strong> ·
      <strong>${parcela.length}</strong> parcela(s) · <strong>${pago}</strong> paga(s)
    </div>
    ${parcelasHtml}
    ` : ''}
    <footer class="doc-assin">
      <div><span>Assinatura do aluno / responsável</span></div>
      <div><span>Assinatura da escola</span></div>
    </footer>
  </section>`;
}

function tabelaParcelas(parcela) {
  if (!parcela.length) {
    return '<p class="empty">Nenhuma parcela gerada — use "Carnê" na matrícula para gerar.</p>';
  }
  const rows = parcela.map((p, i) => {
    const st = p.status === 'paga'
      ? 'PAGO em ' + dataBr(p.data_pagamento)
      : (p.status === 'cancelada' ? 'CANCELADA' : 'Aguardando');
    return `<tr>
      <td class="num">${i + 1}/${parcela.length}</td>
      <td>${dataBr(p.vencimento)}</td>
      <td class="num">${dinheiro(p.valor)}</td>
      <td>${st}</td>
    </tr>`;
  }).join('');
  return `<table class="doc-notch">
    <thead><tr><th>Parcela</th><th>Vencimento</th><th>Valor</th><th>Situação</th></tr></thead>
    <tbody>${rows}</tbody>
  </table>`;
}

carregar().then(() => {
  setTimeout(() => window.print(), 400);
}).catch(() => toast('Erro ao carregar documento.', 'erro'));