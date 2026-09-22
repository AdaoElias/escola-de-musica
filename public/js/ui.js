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

export async function buscarCep(cepInput) {
  const digitos = (cepInput.value || '').replace(/\D/g, '').slice(0, 8);
  cepInput.value = digitos ? digitos.replace(/^(\d{5})(\d{3})$/, '$1-$2') : '';
  if (digitos.length !== 8) return null;
  try {
    const r = await fetch('https://viacep.com.br/ws/' + digitos + '/json/');
    const j = await r.json();
    if (j.erro) return null;
    return {
      endereco: j.logradouro || '',
      bairro: j.bairro || '',
      cidade: j.localidade || '',
      uf: j.uf || '',
    };
  } catch {
    return null;
  }
}