import { guard, logout, perfil } from './auth.js';
import { toast, ligaFecharModais, buscarCep, ligaMascaraTelefone, emailValido, ligaMascaraCpf, formatarCpf, formatarDataBr } from './ui.js';

const sb = await guard();
if (!sb) throw new Error('redirecionado');

const tbody = document.getElementById('tbody');
const modal = document.getElementById('modal');
const form = document.getElementById('form');
const erro = document.getElementById('erro');
const salvarBtn = document.getElementById('btn-salvar');
const campoResponsavel = document.getElementById('campo-responsavel');
let editando = null;

function menorDeIdade(nascimento) {
  if (!nascimento) return false;
  const n = new Date(nascimento + 'T00:00:00');
  const hoje = new Date();
  let idade = hoje.getFullYear() - n.getFullYear();
  const m = hoje.getMonth() - n.getMonth();
  if (m < 0 || (m === 0 && hoje.getDate() < n.getDate())) idade--;
  return idade < 18;
}

function atualizarResponsavel() {
  const menor = menorDeIdade(document.getElementById('nascimento').value);
  campoResponsavel.style.display = menor ? '' : 'none';
  document.getElementById('titulo-responsavel').hidden = !menor;
}

function responsavelObrigatorio() {
  const nome = document.getElementById('responsavel_nome').value.trim();
  const cpf = document.getElementById('responsavel_cpf').value;
  const telefone = document.getElementById('responsavel_telefone').value.trim();
  if (!nome) { erro.textContent = 'Menor de idade exige o nome do responsável.'; return false; }
  if (!cpf || cpf.replace(/\D/g, '').length !== 11) { erro.textContent = 'Menor de idade exige o CPF do responsável.'; return false; }
  if (!telefone) { erro.textContent = 'Menor de idade exige o telefone do responsável.'; return false; }
  return true;
}

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
      <td>${formatarCpf(a.cpf) || '—'}</td>
      <td>${formatarDataBr(a.nascimento)}</td>
      <td>${a.telefone || '—'}</td>
      <td>${a.email || '—'}</td>
      <td>${a.cidade || '—'}</td>
      <td>${a.ativo ? '<span class="badge b-ok">Ativo</span>' : '<span class="badge b-mut">Inativo</span>'}</td>
      <td class="acoes">
        ${a.ativo ? '<button class="mini" data-editar="' + a.id + '">Editar</button>' : ''}
        ${a.ativo ? '<button class="mini danger" data-inativar="' + a.id + '">Inativar</button>' : ''}
      </td>`;
    tbody.appendChild(tr);
  }
  if (!data.length) tbody.innerHTML = '<tr><td colspan="8" class="empty">Nenhum aluno cadastrado ainda.</td></tr>';
}

function mostrarErroTabela(msg) {
  const tr = document.createElement('tr');
  tr.innerHTML = '<td colspan="8" class="error">Erro ao carregar: ' + msg + '</td>';
  tbody.appendChild(tr);
}

function abrirModal(aluno = null) {
  erro.textContent = '';
  salvarBtn.disabled = false;
  editando = aluno;
  document.getElementById('titulo-modal').textContent = aluno ? 'Editar aluno' : 'Novo aluno';
  document.getElementById('id').value = aluno ? aluno.id : '';
  document.getElementById('nome').value = aluno ? aluno.nome : '';
  document.getElementById('cpf').value = aluno ? formatarCpf(aluno.cpf) : '';
  document.getElementById('nascimento').value = aluno ? (aluno.nascimento || '') : '';
  document.getElementById('telefone').value = aluno ? (aluno.telefone || '') : '';
  document.getElementById('email').value = aluno ? (aluno.email || '') : '';
  document.getElementById('observacao').value = aluno ? (aluno.observacao || '') : '';
  document.getElementById('responsavel_nome').value = aluno ? (aluno.responsavel_nome || '') : '';
  document.getElementById('responsavel_cpf').value = aluno ? formatarCpf(aluno.responsavel_cpf) : '';
  document.getElementById('responsavel_telefone').value = aluno ? (aluno.responsavel_telefone || '') : '';
  document.getElementById('parentesco').value = aluno ? (aluno.parentesco || '') : 'pai';
  atualizarResponsavel();
  document.getElementById('cep').value = aluno ? (aluno.cep || '') : '';
  document.getElementById('endereco').value = aluno ? (aluno.endereco || '') : '';
  document.getElementById('bairro').value = aluno ? (aluno.bairro || '') : '';
  document.getElementById('cidade').value = aluno ? (aluno.cidade || '') : '';
  document.getElementById('ativo').checked = aluno ? aluno.ativo : true;
  modal.showModal();
}

async function preencherEndereco() {
  const res = await buscarCep(document.getElementById('cep'));
  if (!res) return toast('CEP não encontrado. Digite o endereço manualmente.', 'erro');
  document.getElementById('endereco').value = res.endereco;
  document.getElementById('bairro').value = res.bairro;
  document.getElementById('cidade').value = res.cidade;
  if (!res.cidade) document.getElementById('cidade').value = res.uf;
}

document.getElementById('novo').addEventListener('click', () => abrirModal());
document.getElementById('buscar-cep').addEventListener('click', preencherEndereco);
document.getElementById('cep').addEventListener('blur', () => {
  if ((document.getElementById('cep').value || '').replace(/\D/g, '').length === 8) preencherEndereco();
});
document.getElementById('cep').addEventListener('keydown', (e) => {
  if (e.key === 'Enter') {
    e.preventDefault();
    preencherEndereco();
  }
});

document.getElementById('nascimento').addEventListener('change', atualizarResponsavel);
ligaMascaraTelefone(document.getElementById('telefone'));
ligaMascaraCpf(document.getElementById('responsavel_cpf'));
ligaMascaraTelefone(document.getElementById('responsavel_telefone'));
ligaMascaraCpf(document.getElementById('cpf'));
document.getElementById('cancelar').addEventListener('click', () => modal.close());
ligaFecharModais(modal);

form.addEventListener('submit', async (e) => {
  e.preventDefault();
  erro.textContent = '';
  salvarBtn.disabled = true;
  const dados = {
    nome: document.getElementById('nome').value.trim(),
    cpf: document.getElementById('cpf').value.trim() || null,
    nascimento: document.getElementById('nascimento').value || null,
    telefone: document.getElementById('telefone').value.trim() || null,
    email: document.getElementById('email').value.trim() || null,
    observacao: document.getElementById('observacao').value.trim() || null,
    responsavel_nome: document.getElementById('responsavel_nome').value.trim() || null,
    responsavel_cpf: document.getElementById('responsavel_cpf').value.trim() || null,
    responsavel_telefone: document.getElementById('responsavel_telefone').value.trim() || null,
    parentesco: document.getElementById('parentesco').value || null,
    cep: document.getElementById('cep').value.trim() || null,
    endereco: document.getElementById('endereco').value.trim() || null,
    bairro: document.getElementById('bairro').value.trim() || null,
    cidade: document.getElementById('cidade').value.trim() || null,
    ativo: document.getElementById('ativo').checked,
  };
  if (!dados.nome) {
    salvarBtn.disabled = false;
    return;
  }
  if (!emailValido(dados.email)) {
    erro.textContent = 'E-mail inválido (deve conter @).';
    salvarBtn.disabled = false;
    return;
  }
  if (menorDeIdade(dados.nascimento) && !responsavelObrigatorio()) {
    salvarBtn.disabled = false;
    return;
  }

  const { error } = editando
    ? await sb.from('alunos').update(dados).eq('id', editando.id)
    : await sb.from('alunos').insert(dados);

  if (error) {
    erro.textContent = 'Erro: ' + error.message;
    salvarBtn.disabled = false;
    return;
  }
  modal.close();
  toast(editando ? 'Aluno atualizado.' : 'Aluno cadastrado.');
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