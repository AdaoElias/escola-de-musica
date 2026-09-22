import { guard, logout, perfil } from './auth.js';
import { toast, ligaFecharModais } from './ui.js';

const sb = await guard();
if (!sb) throw new Error('redirecionado');

const tbody = document.getElementById('tbody');
const tbodyProgresso = document.getElementById('tbody-progresso');
const modal = document.getElementById('modal');
const form = document.getElementById('form');
const erro = document.getElementById('erro');
const salvarBtn = document.getElementById('btn-salvar');
let editando = null;
let avaliarConteudo = null;
let avaliarTurmaId = null;

let turmas = [], matriculas = [], grades = [];
let aulasLista = [];

const me = await perfil(sb);
const admin = me && me.perfil === 'admin';

const campoTurma = document.getElementById('campo-turma');
const campoMatricula = document.getElementById('campo-matricula');
const campoProfessor = document.getElementById('campo-professor');
const campoDesempenho = document.getElementById('campo-desempenho');

document.getElementById('sair').addEventListener('click', logout);
for (const el of document.querySelectorAll('[data-futuro]')) {
  el.addEventListener('click', (e) => e.preventDefault());
}

async function carregarTurmas() {
  const { data } = await sb.from('turmas')
    .select('id, nome, professor_id, professor:professores(nome)')
    .eq('status', 'ativa')
    .order('nome');
  turmas = data || [];
  const sel = document.getElementById('turma_id');
  sel.innerHTML = '';
  for (const t of turmas) {
    const opt = document.createElement('option');
    opt.value = t.id;
    opt.textContent = t.nome;
    sel.appendChild(opt);
  }
}

async function carregarMatriculas() {
  const { data } = await sb.from('matriculas')
    .select('id, aluno_id, aluno:alunos(nome), professor_id, professor:professores(nome)')
    .eq('tipo', 'individual')
    .eq('status', 'ativa')
    .order('id');
  matriculas = data || [];
  const sel = document.getElementById('matricula_id');
  sel.innerHTML = '';
  for (const m of matriculas) {
    const opt = document.createElement('option');
    opt.value = m.id;
    opt.textContent = m.aluno ? m.aluno.nome : 'Aluno #' + m.id;
    sel.appendChild(opt);
  }
}

async function carregarGrades() {
  const { data } = await sb.from('grade_conteudos').select('id, titulo').eq('ativo', true).order('ordem');
  grades = data || [];
  const sel = document.getElementById('grade_id');
  sel.innerHTML = '<option value="">— Conteúdo livre —</option>';
  for (const g of grades) {
    const opt = document.createElement('option');
    opt.value = g.id;
    opt.textContent = g.titulo;
    sel.appendChild(opt);
  }
}

function atualizarTipo() {
  const individual = document.getElementById('tipo').value === 'individual';
  campoTurma.style.display = individual ? 'none' : 'flex';
  campoMatricula.style.display = individual ? 'flex' : 'none';
  campoProfessor.style.display = 'flex';
  campoDesempenho.style.display = individual ? 'grid' : 'none';
  if (!individual) {
    document.getElementById('desempenho').value = '';
    document.getElementById('avaliacao').value = '';
  }
  atualizarProfessor();
}

function atualizarProfessor() {
  const individual = document.getElementById('tipo').value === 'individual';
  const id = Number(individual ? document.getElementById('matricula_id').value : document.getElementById('turma_id').value);
  const arr = individual ? matriculas : turmas;
  const item = arr.find((x) => x.id === id);
  document.getElementById('professor_display').value = item && item.professor
    ? item.professor.nome
    : (admin ? '(defina abaixo)' : '—');
}

document.getElementById('tipo').addEventListener('change', atualizarTipo);
document.getElementById('turma_id').addEventListener('change', atualizarProfessor);
document.getElementById('matricula_id').addEventListener('change', atualizarProfessor);

document.getElementById('grade_id').addEventListener('change', (e) => {
  const g = grades.find((x) => x.id === Number(e.target.value));
  const titulo = document.getElementById('titulo');
  if (g && !titulo.value.trim()) titulo.value = g.titulo;
});

function barraProgresso(total, ministrados, percentual) {
  const p = total ? Math.min(100, Math.max(0, percentual || 0)) : 0;
  const wrapper = document.createElement('div');
  wrapper.className = 'prog';
  wrapper.innerHTML = `
    <div class="prog-bar"><div class="prog-fill" style="width:${p}%"></div></div>
    <small>${ministrados || 0}/${total || 0} itens · ${p}%</small>`;
  return wrapper;
}

async function carregarProgresso() {
  tbodyProgresso.innerHTML = '';
  const [r1, r2] = await Promise.all([
    sb.from('vw_progresso_turma').select('*'),
    sb.from('vw_progresso_aluno').select('*'),
  ]);

  const linhas = [];
  for (const t of r1.data || []) {
    linhas.push({ rotulo: 'Turma — ' + t.turma, total: t.total_itens, ministrados: t.ministrados, p: t.percentual });
  }
  for (const a of r2.data || []) {
    linhas.push({ rotulo: 'Individual — ' + a.aluno, total: a.total_itens, ministrados: a.ministrados, p: a.percentual });
  }

  if (!linhas.length) {
    const tr = document.createElement('tr');
    tr.innerHTML = '<td colspan="2" class="error">' +
      (r1.error ? 'Erro ao carregar progresso: ' + r1.error.message + ' (execute MIGRACAO_ETAPA4.sql no Supabase)' : 'Sem dados de progresso ainda.') +
      '</td>';
    tbodyProgresso.appendChild(tr);
    return;
  }

  for (const l of linhas) {
    const tr = document.createElement('tr');
    const td1 = document.createElement('td');
    td1.textContent = l.rotulo;
    const td2 = document.createElement('td');
    td2.appendChild(barraProgresso(l.total, l.ministrados, l.p));
    tr.appendChild(td1);
    tr.appendChild(td2);
    tbodyProgresso.appendChild(tr);
  }
}

async function carregar() {
  const { data, error } = await sb.from('conteudos_ministrados')
    .select('*, turma:turmas(nome), matricula:matriculas(aluno:alunos(nome)), professor:professores(nome), grade:grade_conteudos(titulo)')
    .order('data_aula', { ascending: false })
    .order('criado_em', { ascending: false });
  if (error) return mostrarErroTabela(error.message);

  const ids = (data || []).filter((c) => c.matricula_id).map((c) => c.id);
  const desempenhoMap = {};
  if (ids.length) {
    const { data: dds } = await sb.from('desempenhos').select('conteudo_id, desempenho').in('conteudo_id', ids);
    for (const d of dds || []) desempenhoMap[d.conteudo_id] = d.desempenho;
  }

  tbody.innerHTML = '';
  aulasLista = [];
  for (const c of data || []) {
    const local = c.turma_id
      ? (c.turma ? c.turma.nome : 'Turma #' + c.turma_id)
      : (c.matricula && c.matricula.aluno ? c.matricula.aluno.nome : 'Individual #' + c.matricula_id);

    let conteudo;
    if (c.grade) conteudo = c.grade.titulo + (c.titulo && c.titulo !== c.grade.titulo ? ' — ' + c.titulo : '');
    else conteudo = c.titulo || '—';

    aulasLista.push({ id: c.id, rotulo: (local + ' — ' + conteudo).slice(0, 60) });

    const tr = document.createElement('tr');
    tr.innerHTML = `
      <td>${c.data_aula}</td>
      <td>${local}</td>
      <td>${c.professor ? c.professor.nome : '—'}</td>
      <td>${conteudo}</td>
      <td>${c.evolucao_turma != null ? Number(c.evolucao_turma) + '%' : '—'}</td>
      <td>${desempenhoMap[c.id] != null ? Number(desempenhoMap[c.id]) + '%' : '—'}</td>
      <td class="acoes">
        <button class="mini" data-editar="${c.id}">Editar</button>
        ${c.turma_id ? '<button class="mini" data-avaliar="' + c.id + '">Avaliar</button>' : ''}
        <button class="mini danger" data-excluir="${c.id}">Excluir</button>
      </td>`;
    tbody.appendChild(tr);
  }
  if (!data.length) tbody.innerHTML = '<tr><td colspan="7" class="empty">Nenhuma aula lançada ainda.</td></tr>';
}

function mostrarErroTabela(msg) {
  const tr = document.createElement('tr');
  tr.innerHTML = '<td colspan="7" class="error">Erro ao carregar: ' + msg + '</td>';
  tbody.appendChild(tr);
}

function abrirModal(aula = null) {
  erro.textContent = '';
  salvarBtn.disabled = false;
  editando = aula;
  document.getElementById('titulo-modal').textContent = aula ? 'Editar aula' : 'Lançar aula';
  document.getElementById('id').value = aula ? aula.id : '';
  document.getElementById('tipo').value = aula ? (aula.turma_id ? 'turma' : 'individual') : 'turma';
  const turmaSel = document.getElementById('turma_id');
  turmaSel.value = aula && aula.turma_id ? aula.turma_id : (turmas[0] ? turmas[0].id : '');
  const matSel = document.getElementById('matricula_id');
  matSel.value = aula && aula.matricula_id ? aula.matricula_id : (matriculas[0] ? matriculas[0].id : '');
  document.getElementById('data_aula').value = aula ? aula.data_aula : new Date().toISOString().slice(0, 10);
  document.getElementById('grade_id').value = aula && aula.grade_id ? aula.grade_id : '';
  document.getElementById('titulo').value = aula ? (aula.titulo || '') : '';
  document.getElementById('descricao').value = aula ? (aula.descricao || '') : '';
  document.getElementById('evolucao_turma').value = aula && aula.turma_id ? aula.evolucao_turma : '';
  document.getElementById('observacoes').value = aula ? (aula.observacoes || '') : '';
  document.getElementById('desempenho').value = aula && aula.matricula_id ? (aula._desempenho || '') : '';
  document.getElementById('avaliacao').value = aula && aula.matricula_id ? (aula._avaliacao || '') : '';
  atualizarTipo();
  modal.showModal();
}

async function carregarDesempenhoDaEditada(aula) {
  if (!aula || !aula.matricula_id) return aula;
  const { data } = await sb.from('desempenhos').select('desempenho, avaliacao').eq('conteudo_id', aula.id).maybeSingle();
  aula._desempenho = data ? data.desempenho : '';
  aula._avaliacao = data ? (data.avaliacao || '') : '';
  return aula;
}

document.getElementById('novo').addEventListener('click', () => abrirModal());
document.getElementById('cancelar').addEventListener('click', () => modal.close());
ligaFecharModais(modal);
document.querySelector('[data-fechar-avaliar]').addEventListener('click', () => {
  document.getElementById('modal-avaliar').close();
});

form.addEventListener('submit', async (e) => {
  e.preventDefault();
  erro.textContent = '';
  salvarBtn.disabled = true;

  const tipo = document.getElementById('tipo').value;
  const serie = tipo === 'turma'
    ? turmas.find((x) => x.id === Number(document.getElementById('turma_id').value))
    : matriculas.find((x) => x.id === Number(document.getElementById('matricula_id').value));
  if (!serie) {
    erro.textContent = 'Selecione a turma ou o aluno.';
    salvarBtn.disabled = false;
    return;
  }

  const gradeId = document.getElementById('grade_id').value
    ? Number(document.getElementById('grade_id').value)
    : null;
  const evolucao = document.getElementById('evolucao_turma').value;
  const evolucaoVal = evolucao === '' ? null : Number(evolucao);

  const dados = {
    data_aula: document.getElementById('data_aula').value || new Date().toISOString().slice(0, 10),
    titulo: document.getElementById('titulo').value.trim(),
    descricao: document.getElementById('descricao').value.trim() || null,
    observacoes: document.getElementById('observacoes').value.trim() || null,
    professor_id: serie.professor_id,
    grade_id: gradeId,
    turma_id: tipo === 'turma' ? serie.id : null,
    matricula_id: tipo === 'individual' ? serie.id : null,
    evolucao_turma: tipo === 'turma' ? evolucaoVal : null,
  };
  if (!dados.titulo) {
    salvarBtn.disabled = false;
    return;
  }
  if (dados.evolucao_turma != null && (isNaN(dados.evolucao_turma) || dados.evolucao_turma < 0 || dados.evolucao_turma > 100)) {
    erro.textContent = 'Evolução deve ficar entre 0 e 100.';
    salvarBtn.disabled = false;
    return;
  }

  let id = editando ? editando.id : null;
  if (editando) {
    const { error } = await sb.from('conteudos_ministrados').update(dados).eq('id', editando.id);
    if (error) {
      erro.textContent = 'Erro: ' + error.message;
      salvarBtn.disabled = false;
      return;
    }
  } else {
    const { data, error } = await sb.from('conteudos_ministrados').insert(dados).select('id').single();
    if (error) {
      erro.textContent = 'Erro: ' + error.message;
      salvarBtn.disabled = false;
      return;
    }
    id = data.id;
  }

  if (tipo === 'individual' && id) {
    const valor = document.getElementById('desempenho').value;
    const aval = document.getElementById('avaliacao').value.trim();
    const alunoId = serie.aluno_id;
    if (valor !== '') {
      await sb.from('desempenhos').upsert({
        aluno_id: alunoId,
        conteudo_id: id,
        desempenho: Number(valor),
        avaliacao: aval || null,
        data: dados.data_aula,
      }, { onConflict: 'aluno_id,conteudo_id' });
    } else {
      await sb.from('desempenhos').delete().eq('aluno_id', alunoId).eq('conteudo_id', id);
    }
  }

  modal.close();
  toast(editando ? 'Aula atualizada.' : 'Aula lançada.');
  carregar();
  carregarProgresso();
});

tbody.addEventListener('click', async (e) => {
  const btnEditar = e.target.closest('[data-editar]');
  const btnExcluir = e.target.closest('[data-excluir]');
  const btnAvaliar = e.target.closest('[data-avaliar]');

  if (btnEditar) {
    const id = Number(btnEditar.dataset.editar);
    const { data } = await sb.from('conteudos_ministrados').select('*').eq('id', id).single();
    abrirModal(await carregarDesempenhoDaEditada(data));
  } else if (btnExcluir) {
    const id = Number(btnExcluir.dataset.excluir);
    if (!confirm('Excluir este lançamento? Desempenhos vinculados também serão removidos.')) return;
    const { error } = await sb.from('conteudos_ministrados').delete().eq('id', id);
    if (!error) {
      carregar();
      carregarProgresso();
    }
  } else if (btnAvaliar) {
    const reg = aulasLista.find((x) => x.id === Number(btnAvaliar.dataset.avaliar));
    const { data: aula } = await sb.from('conteudos_ministrados').select('id, turma_id').eq('id', Number(btnAvaliar.dataset.avaliar)).single();
    abrirAvaliacao(
      Number(btnAvaliar.dataset.avaliar),
      aula.turma_id,
      reg ? reg.rotulo : 'Aula'
    );
  }
});

async function abrirAvaliacao(conteudoId, turmaId, titulo) {
  avaliarConteudo = conteudoId;
  avaliarTurmaId = turmaId;
  document.getElementById('avaliar-titulo').textContent = 'Avaliar alunos — ' + titulo;
  document.getElementById('erro-avaliar').textContent = '';

  const corpo = document.getElementById('avaliar-corpo');
  corpo.innerHTML = '';

  const [rMats, rDes] = await Promise.all([
    sb.from('matriculas').select('aluno:alunos(id, nome)').eq('turma_id', turmaId).eq('status', 'ativa').order('aluno_id'),
    sb.from('desempenhos').select('aluno_id, desempenho, avaliacao').eq('conteudo_id', conteudoId),
  ]);

  const dds = rDes.data || [];
  for (const m of rMats.data || []) {
    if (!m.aluno) continue;
    const d = dds.find((x) => x.aluno_id === m.aluno.id);
    const linha = document.createElement('div');
    linha.className = 'avaliar-linha';
    linha.dataset.aluno = m.aluno.id;
    linha.innerHTML = `
      <strong class="avaliar-nome">${m.aluno.nome}</strong>
      <div class="grid2">
        <label>Desempenho (%) <input type="number" data-campo="desempenho" min="0" max="100" step="0.01" value="${d ? d.desempenho : ''}"></label>
        <label>Avaliação <input type="text" data-campo="avaliacao" value="${d ? (d.avaliacao || '') : ''}"></label>
      </div>`;
    corpo.appendChild(linha);
  }

  if (!(rMats.data || []).length) {
    corpo.innerHTML = '<p class="error">Nenhum aluno ativo nesta turma.</p>';
  }

  document.getElementById('modal-avaliar').showModal();
}

document.getElementById('fechar-avaliar').addEventListener('click', () => {
  document.getElementById('modal-avaliar').close();
});

document.getElementById('salvar-avaliacoes').addEventListener('click', async () => {
  const erroAvaliar = document.getElementById('erro-avaliar');
  erroAvaliar.textContent = '';
  const upserts = [];
  const deletes = [];

  for (const linha of document.querySelectorAll('.avaliar-linha')) {
    const alunoId = Number(linha.dataset.aluno);
    const val = Number(linha.querySelector('[data-campo="desempenho"]').value);
    const aval = linha.querySelector('[data-campo="avaliacao"]').value.trim();
    if (val) {
      upserts.push({
        aluno_id: alunoId,
        conteudo_id: avaliarConteudo,
        desempenho: val,
        avaliacao: aval || null,
        data: new Date().toISOString().slice(0, 10),
      });
    } else {
      deletes.push(alunoId);
    }
  }

  const ops = [];
  if (upserts.length) {
    ops.push(sb.from('desempenhos').upsert(upserts, { onConflict: 'aluno_id,conteudo_id' }));
  }
  for (const alunoId of deletes) {
    ops.push(sb.from('desempenhos').delete().eq('aluno_id', alunoId).eq('conteudo_id', avaliarConteudo));
  }

  const resultados = await Promise.all(ops);
  const firstError = resultados.find((r) => r.error);
  if (firstError) {
    erroAvaliar.textContent = 'Erro: ' + firstError.error.message;
    return;
  }
  document.getElementById('modal-avaliar').close();
  toast('Avaliações salvas.');
  carregar();
});

await Promise.all([carregarTurmas(), carregarMatriculas(), carregarGrades()]);
carregar();
carregarProgresso();