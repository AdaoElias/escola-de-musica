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

const me = await perfil(sb);
const admin = me && me.perfil === 'admin';

document.getElementById('sair').addEventListener('click', logout);
for (const el of document.querySelectorAll('[data-futuro]')) {
  el.addEventListener('click', (e) => e.preventDefault());
}

function intervaloParaMinutos(valor) {
  if (!valor) return 0;
  const s = String(valor).trim();
  const shorts = /^(\d+):(\d{2})(?::(\d{2}))?$/.exec(s);
  if (shorts) return Number(shorts[1]) * 60 + Number(shorts[2]);
  const iso = /^P(?:(\d+)D)?(?:T(?:(\d+)H)?(?:(\d+)M)?(?:(\d+(?:\.\d+)?)S)?)?$/.exec(s);
  if (iso) {
    return (Number(iso[1] || 0) * 1440) + (Number(iso[2] || 0) * 60) + Number(iso[3] || 0);
  }
  return 0;
}

function minutosParaIntervalo(min) {
  const n = Number(min);
  if (!n || n <= 0) return null;
  return 'PT' + n + 'M';
}

function exibirMinutos(min) {
  if (!min) return '—';
  return min % 60 === 0 ? (min / 60) + 'h' : min + ' min';
}

async function carregar() {
  const { data, error } = await sb.from('grade_conteudos').select('*').order('ordem').order('titulo');
  if (error) return mostrarErroTabela(error.message);
  tbody.innerHTML = '';
  for (const g of data) {
    const tr = document.createElement('tr');
    tr.innerHTML = `
      <td>${g.ordem}</td>
      <td>${g.titulo}</td>
      <td>${g.descricao || '—'}</td>
      <td>${g.modulo || '—'}</td>
      <td>${g.nivel || '—'}</td>
      <td>${exibirMinutos(intervaloParaMinutos(g.tempo_estimado))}</td>
      <td>${g.ativo ? '<span class="badge b-ok">Ativo</span>' : '<span class="badge b-mut">Inativo</span>'}</td>
      <td class="acoes">
        <button class="mini" data-editar="${g.id}">Editar</button>
        ${admin ? '<button class="mini danger" data-excluir="' + g.id + '">Excluir</button>' : ''}
      </td>`;
    tbody.appendChild(tr);
  }
  if (!data.length) tbody.innerHTML = '<tr><td colspan="8" class="empty">Nenhum item na grade ainda. Clique em Novo item.</td></tr>';
}

function mostrarErroTabela(msg) {
  const tr = document.createElement('tr');
  tr.innerHTML = '<td colspan="8" class="error">Erro ao carregar: ' + msg + '</td>';
  tbody.appendChild(tr);
}

function abrirModal(item = null) {
  erro.textContent = '';
  salvarBtn.disabled = false;
  editando = item;
  document.getElementById('titulo-modal').textContent = item ? 'Editar item' : 'Novo item da grade';
  document.getElementById('id').value = item ? item.id : '';
  document.getElementById('ordem').value = item ? item.ordem : '';
  document.getElementById('tempo_estimado').value = item ? intervaloParaMinutos(item.tempo_estimado) : '';
  document.getElementById('titulo').value = item ? item.titulo : '';
  document.getElementById('descricao').value = item ? (item.descricao || '') : '';
  document.getElementById('modulo').value = item ? (item.modulo || '') : '';
  document.getElementById('nivel').value = item ? (item.nivel || 'Iniciante') : 'Iniciante';
  document.getElementById('ativo').checked = item ? item.ativo !== false : true;
  modal.showModal();
}

document.getElementById('novo').addEventListener('click', () => abrirModal());
document.getElementById('cancelar').addEventListener('click', () => modal.close());
ligaFecharModais(modal);

form.addEventListener('submit', async (e) => {
  e.preventDefault();
  erro.textContent = '';
  salvarBtn.disabled = true;
  const dados = {
    ordem: Number(document.getElementById('ordem').value || 0),
    tempo_estimado: minutosParaIntervalo(document.getElementById('tempo_estimado').value),
    titulo: document.getElementById('titulo').value.trim(),
    descricao: document.getElementById('descricao').value.trim() || null,
    modulo: document.getElementById('modulo').value.trim() || null,
    nivel: document.getElementById('nivel').value,
    ativo: document.getElementById('ativo').checked,
  };
  if (!dados.titulo) {
    salvarBtn.disabled = false;
    return;
  }

  const { error } = editando
    ? await sb.from('grade_conteudos').update(dados).eq('id', editando.id)
    : await sb.from('grade_conteudos').insert(dados);

  if (error) {
    erro.textContent = 'Erro: ' + error.message;
    salvarBtn.disabled = false;
    return;
  }
  modal.close();
  toast(editando ? 'Item atualizado.' : 'Item da grade criado.');
  carregar();
});

tbody.addEventListener('click', async (e) => {
  const btnEditar = e.target.closest('[data-editar]');
  const btnExcluir = e.target.closest('[data-excluir]');
  if (btnEditar) {
    const id = Number(btnEditar.dataset.editar);
    const { data } = await sb.from('grade_conteudos').select('*').eq('id', id).single();
    abrirModal(data);
  } else if (btnExcluir) {
    const id = Number(btnExcluir.dataset.excluir);
    if (!confirm('Excluir este item da grade? Aulas já lançadas permanecem.')) return;
    const { error } = await sb.from('grade_conteudos').delete().eq('id', id);
    if (!error) carregar();
  }
});

if (!admin) document.getElementById('novo').hidden = true;
carregar();