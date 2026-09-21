const statusEl = document.getElementById('status');
const subEl = document.getElementById('supabase-msg');

async function init() {
  try {
    const res = await fetch('/api/hello');
    const data = await res.json();
    statusEl.textContent = '✅ ' + data.message;
    statusEl.className = 'status ok';
  } catch (err) {
    statusEl.textContent = '❌ Função serverless não respondeu';
    statusEl.className = 'status err';
    subEl.textContent = 'Rode: netlify dev';
    return;
  }

  if (window.SUPABASE_URL) {
    subEl.textContent = 'Banco de dados: ' + window.SUPABASE_URL;
    try {
      const res = await fetch('/api/health');
      const data = await res.json();
      subEl.textContent = 'Banco de dados: conectado ✓ (' + data.db + ')';
    } catch {
      subEl.textContent = 'Banco de dados: função setada, porém sem resposta.';
    }
  } else {
    subEl.textContent = 'Banco de dados: configure SUPABASE_URL para ativar.';
  }
}

init();