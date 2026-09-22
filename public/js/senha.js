import { getSupabase } from './supabase.js';
import { toast, ligaFecharModais } from './ui.js';

const topbar = document.querySelector('.topbar');
const sair = document.getElementById('sair');
if (!topbar || !sair || document.getElementById('btn-senha')) {
  throw new Error('sem topbar');
}

const bt = document.createElement('button');
bt.id = 'btn-senha';
bt.type = 'button';
bt.className = 'link';
bt.textContent = 'Senha';
topbar.insertBefore(bt, sair);

const dialog = document.createElement('dialog');
dialog.id = 'modal-senha';
dialog.innerHTML = `
  <form id="form-senha" class="form">
    <div class="modal-head">
      <h3>Trocar senha</h3>
      <button type="button" class="x" data-fechar aria-label="Fechar">×</button>
    </div>
    <div class="modal-body">
      <p class="sub">Você continuará logado após a troca.</p>
      <label class="field">Nova senha <span class="obrigatorio">*</span>
        <input type="password" id="senha-nova" minlength="6" required autocomplete="new-password">
        <small>mínimo de 6 caracteres</small>
      </label>
      <label class="field">Confirmar nova senha <span class="obrigatorio">*</span>
        <input type="password" id="senha-confirma" minlength="6" required autocomplete="new-password">
      </label>
    </div>
    <div class="modal-foot">
      <p class="error" id="erro-senha"></p>
      <div class="row gap">
        <button type="button" class="btn ghost" id="cancelar-senha">Cancelar</button>
        <button type="submit" class="btn" id="salvar-senha">Salvar senha</button>
      </div>
    </div>
  </form>`;
document.body.appendChild(dialog);
ligaFecharModais(dialog);

bt.addEventListener('click', () => {
  document.getElementById('senha-nova').value = '';
  document.getElementById('senha-confirma').value = '';
  document.getElementById('erro-senha').textContent = '';
  dialog.showModal();
});
document.getElementById('cancelar-senha').addEventListener('click', () => dialog.close());

document.getElementById('form-senha').addEventListener('submit', async (e) => {
  e.preventDefault();
  const nova = document.getElementById('senha-nova').value;
  const confirma = document.getElementById('senha-confirma').value;
  const erro = document.getElementById('erro-senha');
  const salvar = document.getElementById('salvar-senha');
  erro.textContent = '';
  if (nova.length < 6) {
    erro.textContent = 'A senha deve ter pelo menos 6 caracteres.';
    return;
  }
  if (nova !== confirma) {
    erro.textContent = 'As senhas não conferem.';
    return;
  }
  salvar.disabled = true;
  salvar.textContent = 'Salvando…';
  try {
    const sb = await getSupabase();
    const { error } = await sb.auth.updateUser({ password: nova });
    if (error) throw error;
    dialog.close();
    toast('Senha alterada com sucesso.', 'ok');
  } catch (err) {
    erro.textContent = err.message;
  } finally {
    salvar.disabled = false;
    salvar.textContent = 'Salvar senha';
  }
});