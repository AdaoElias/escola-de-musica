import { guard, logout, perfil } from './auth.js';
import { toast, ligaFecharModais } from './ui.js';

const sb = await guard();
if (!sb) throw new Error('redirecionado');

const me = await perfil(sb);
const admin = me && me.perfil === 'admin';

const tbody = document.getElementById('tbody');
const modalBaixar = document.getElementById('modal-baixar');
const modalLancar = document.getElementById('modal-lancar');
const formBaixar = document.getElementById('form-baixar');
const formLancar = document.getElementById('form-lancar');

document.getElementById('sair').addEventListener('click', logout);
for (const el of document.querySelectorAll('[data-futuro]')) {
  el.addEventListener('click', (e) => e.preventDefault());
}

const hoje = new Date();
const iso = hoje.toISOString().slice(0, 10);
const primeiroDoMes = iso.slice(0, 8) + '01';
const mesAtual = iso.slice(0, 7);

function dinheiro(v) {
  return 'R$ ' + Number(v || 0).toLocaleString('pt-BR', { minimumFractionDigits: 2 });
}
function menorDeIdade(aluno) {
  if (!aluno || !aluno.nascimento) return false;
  const n = new Date(aluno.nascimento + 'T00:00:00');
  const hoje = new Date();
  let idade = hoje.getFullYear() - n.getFullYear();
  const m = hoje.getMonth() - n.getMonth();
  if (m < 0 || (m === 0 && hoje.getDate() < n.getDate())) idade--;
  return idade < 18;
}
function dataBr(d) {
  return d ? d.slice(0, 10).split('-').reverse().join('/') : '—';
}
function mesBr(m) {
  if (!m) return '—';
  const [a, mm] = m.slice(0, 10).split('-');
  return new Date(Number(a), Number(mm) - 1, 1)
    .toLocaleDateString('pt-BR', { month: 'long', year: 'numeric' });
}

const BADGES = {
  pendente: '<span class="badge b-warn">Pendente</span>',
  atrasada: '<span class="badge b-err">Atrasada</span>',
  paga: '<span class="badge b-ok">Paga</span>',
  cancelada: '<span class="badge b-mut">Cancelada</span>',
};

if (!admin) {
  document.querySelector('.wrap').innerHTML =
    '<div class="alert danger"><div><span class="alert-title">Acesso restrito</span>' +
    '<p>O módulo financeiro é exclusivo do administrador (RF30).</p></div></div>';
} else {
  iniciar();
}

async function iniciar() {
  document.getElementById('resumo-mes').textContent =
    'Competência de ' + mesBr(primeiroDoMes) + ' · atualizado em ' + dataBr(iso);

  document.getElementById('gerar').addEventListener('click', gerar);
  document.getElementById('novo').addEventListener('click', abrirLancar);
  document.getElementById('filtro-status').addEventListener('change', carregar);
  document.getElementById('filtro-mes').addEventListener('change', carregar);
  document.getElementById('cancelar-baixar').addEventListener('click', () => modalBaixar.close());
  document.getElementById('cancelar-lancar').addEventListener('click', () => modalLancar.close());
  ligaFecharModais(modalBaixar);
  ligaFecharModais(modalLancar);
  formBaixar.addEventListener('submit', salvarBaixar);
  formLancar.addEventListener('submit', salvarLancar);
  tbody.addEventListener('click', acoesTabela);

  await gerar(true);
  await Promise.all([carregarKpis(), carregar()]);
  await popularAlunos();
}

async function gerar(silencioso = false) {
  const { data, error } = await sb.rpc('gerar_mensalidades');
  if (error) {
    if (!silencioso) toast('Erro ao gerar: ' + error.message, 'erro');
    return;
  }
  if (data > 0) toast(data + ' cobrança(s) de mensalidade gerada(s).');
  else if (!silencioso) toast('Todas as mensalidades já estão geradas.');
  await Promise.all([carregarKpis(), carregar()]);
}

async function carregarKpis() {
  const hojeISO = iso;
  const [rMes, rAtraso] = await Promise.all([
    sb.from('financeiro').select('valor, status').eq('competencia', primeiroDoMes),
    sb.from('financeiro').select('id, valor').lt('vencimento', hojeISO)
      .in('status', ['pendente', 'atrasada']),
  ]);
  const linhas = rMes.data || [];
  const aReceber = linhas
    .filter((l) => l.status === 'pendente' || l.status === 'atrasada')
    .reduce((s, l) => s + Number(l.valor || 0), 0);
  const recebido = linhas
    .filter((l) => l.status === 'paga')
    .reduce((s, l) => s + Number(l.valor || 0), 0);
  const atraso = rAtraso.data || [];
  const somaAtraso = atraso.reduce((s, l) => s + Number(l.valor || 0), 0);

  const kpis = document.getElementById('kpis');
  kpis.innerHTML =
    kpi('k-warn', 'A receber no mês', dinheiro(aReceber),
      linhas.filter((l) => l.status !== 'paga' && l.status !== 'cancelada').length + ' lançamento(s) aberto(s)') +
    kpi('k-ok', 'Recebido no mês', dinheiro(recebido),
      linhas.filter((l) => l.status === 'paga').length + ' pagamento(s)') +
    kpi('k-err', 'Em atraso', dinheiro(somaAtraso),
      atraso.length ? atraso.length + ' lançamento(s) vencido(s)' : 'nenhum atraso');
}

function kpi(classe, label, value, foot) {
  return `<div class="kpi ${classe}">
    <div class="kpi-top"><span class="kpi-label">${label}</span></div>
    <div class="kpi-value">${value}</div>
    <div class="kpi-foot">${foot}</div></div>`;
}

async function carregar() {
  let q = sb.from('financeiro')
    .select('*, aluno:alunos(nome, nascimento, responsavel_nome)')
    .order('vencimento', { ascending: true })
    .order('id', { ascending: false });

  const st = document.getElementById('filtro-status').value;
  if (st === 'a_receber') q = q.in('status', ['pendente', 'atrasada']);
  else if (st !== 'todas') q = q.eq('status', st);

  const mes = document.getElementById('filtro-mes').value;
  if (mes) q = q.eq('competencia', mes + '-01');

  const { data, error } = await q;
  if (error) return mostrarErro(error.message);

  tbody.innerHTML = '';
  let soma = 0;
  for (const l of data) {
    if (l.status !== 'cancelada') soma += Number(l.valor || 0);
    const tr = document.createElement('tr');
    const pendente = l.status === 'pendente' || l.status === 'atrasada';
    const resp = menorDeIdade(l.aluno);
    const nomeAluno = l.aluno
      ? l.aluno.nome + (resp && l.aluno.responsavel_nome ? '<br><small>menor — resp. ' + l.aluno.responsavel_nome + '</small>' : '')
      : '—';
    tr.innerHTML = `
      <td>${nomeAluno}</td>
      <td>${l.descricao}</td>
      <td>${mesBr(l.competencia)}</td>
      <td>${dataBr(l.vencimento)}</td>
      <td>${dinheiro(l.valor)}</td>
      <td>${BADGES[l.status] || l.status}</td>
      <td class="acoes">
        ${l.matricula_id ? '<button class="mini" data-carne="' + l.matricula_id + '">Carnê</button>' : ''}
        ${pendente ? '<button class="mini" data-baixar="' + l.id + '">Baixar</button>' : ''}
        ${pendente ? '<button class="mini danger" data-cancelar="' + l.id + '">Cancelar</button>' : ''}
      </td>`;
    tbody.appendChild(tr);
  }

  document.getElementById('total-lista').textContent =
    data.length
      ? data.length + ' lançamento(s) · total ' + dinheiro(soma)
      : '';

  if (!data.length) {
    tbody.innerHTML = '<tr><td colspan="7" class="empty">Nenhum lançamento com esses filtros.</td></tr>';
  }
}

function mostrarErro(msg) {
  tbody.innerHTML = '<tr><td colspan="7" class="error">Erro ao carregar: ' + msg + '</td></tr>';
}

async function popularAlunos() {
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

async function acoesTabela(e) {
  const btnBaixar = e.target.closest('[data-baixar]');
  const btnCancelar = e.target.closest('[data-cancelar]');
  const btnCarne = e.target.closest('[data-carne]');
  if (btnCarne) {
    window.open('/carne.html?matricula=' + btnCarne.dataset.carne + '&tipo=carne', '_blank');
  } else if (btnBaixar) {
    const id = Number(btnBaixar.dataset.baixar);
    const { data } = await sb.from('financeiro').select('*, aluno:alunos(nome)').eq('id', id).single();
    if (!data) return;
    document.getElementById('baixar-id').value = data.id;
    document.getElementById('baixar-resumo').textContent =
      (data.aluno ? data.aluno.nome : '—') + ' · ' + data.descricao + ' · ' + dinheiro(data.valor);
    document.getElementById('data_pagamento').value = iso;
    document.getElementById('forma_pagamento').value = 'pix';
    document.getElementById('erro-baixar').textContent = '';
    modalBaixar.showModal();
  } else if (btnCancelar) {
    const id = Number(btnCancelar.dataset.cancelar);
    if (!confirm('Cancelar este lançamento? Ele permanece no histórico (RN08).')) return;
    const { error } = await sb.from('financeiro').update({ status: 'cancelada' }).eq('id', id);
    if (error) return toast('Erro: ' + error.message, 'erro');
    toast('Lançamento cancelado.');
    await Promise.all([carregarKpis(), carregar()]);
  }
}

async function salvarBaixar(e) {
  e.preventDefault();
  const erro = document.getElementById('erro-baixar');
  erro.textContent = '';
  const btn = document.getElementById('salvar-baixar');
  btn.disabled = true;
  const { error } = await sb.from('financeiro').update({
    status: 'paga',
    data_pagamento: document.getElementById('data_pagamento').value,
    forma_pagamento: document.getElementById('forma_pagamento').value,
  }).eq('id', Number(document.getElementById('baixar-id').value));
  if (error) {
    erro.textContent = 'Erro: ' + error.message;
    btn.disabled = false;
    return;
  }
  btn.disabled = false;
  modalBaixar.close();
  toast('Pagamento registrado.');
  await Promise.all([carregarKpis(), carregar()]);
}

function abrirLancar() {
  document.getElementById('erro-lancar').textContent = '';
  document.getElementById('salvar-lancar').disabled = false;
  document.getElementById('descricao').value = '';
  document.getElementById('valor').value = '';
  document.getElementById('vencimento').value = iso;
  document.getElementById('competencia').value = mesAtual;
  document.getElementById('tipo').value = 'ajuste';
  modalLancar.showModal();
}

async function salvarLancar(e) {
  e.preventDefault();
  const erro = document.getElementById('erro-lancar');
  erro.textContent = '';
  const btn = document.getElementById('salvar-lancar');
  btn.disabled = true;

  const aluno = Number(document.getElementById('aluno_id').value);
  const descricao = document.getElementById('descricao').value.trim();
  const valor = Number(document.getElementById('valor').value);
  const vencimento = document.getElementById('vencimento').value;
  const competencia = document.getElementById('competencia').value;
  const tipo = document.getElementById('tipo').value;

  if (!aluno || !descricao || !(valor > 0) || !vencimento || !competencia) {
    erro.textContent = 'Preencha aluno, descrição, valor, vencimento e competência.';
    btn.disabled = false;
    return;
  }

  const { error } = await sb.from('financeiro').insert({
    aluno_id: aluno,
    tipo,
    descricao,
    valor,
    vencimento,
    competencia: competencia + '-01',
    status: 'pendente',
  });
  if (error) {
    erro.textContent = 'Erro: ' + error.message;
    btn.disabled = false;
    return;
  }
  btn.disabled = false;
  modalLancar.close();
  toast('Lançamento criado.');
  await Promise.all([carregarKpis(), carregar()]);
}