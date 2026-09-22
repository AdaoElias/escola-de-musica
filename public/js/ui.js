export function toast(mensagem, tipo = 'ok') {
  let box = document.querySelector('.toasts');
  if (!box) {
    box = document.createElement('div');
    box.className = 'toasts';
    document.body.appendChild(box);
  }
  const el = document.createElement('div');
  el.className = 'toast ' + (tipo === 'erro' ? 'erro' : 'ok');
  el.textContent = mensagem;
  box.appendChild(el);
  setTimeout(() => {
    el.style.opacity = '0';
    el.style.transition = 'opacity 0.3s';
    setTimeout(() => el.remove(), 320);
  }, 3200);
}

export function ligaFecharModais(modal) {
  for (const el of document.querySelectorAll('[data-fechar]')) {
    el.addEventListener('click', () => modal.close());
  }
}