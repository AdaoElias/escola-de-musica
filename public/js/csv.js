import { toast } from './ui.js';

function esc(v) {
  const s = String(v === null || v === undefined ? '' : v);
  return /[";\n]/.test(s) ? '"' + s.replace(/"/g, '""') + '"' : s;
}

export function baixarCsv(nome, cols, linhas) {
  const out = [cols.map(esc).join(';')];
  linhas.forEach((r) => out.push(r.map(esc).join(';')));
  const blob = new Blob(['\uFEFF' + out.join('\r\n')], { type: 'text/csv;charset=utf-8;' });
  const a = document.createElement('a');
  a.href = URL.createObjectURL(blob);
  a.download = nome.replace(/\.csv$/i, '') + '.csv';
  document.body.appendChild(a);
  a.click();
  a.remove();
  URL.revokeObjectURL(a.href);
  toast('CSV exportado.', 'ok');
}

export function exportarTabela(tabela, nome) {
  const ths = [...tabela.querySelectorAll('thead th')]
    .map((th) => th.textContent.trim().replace(/\s+/g, ' '))
    .filter((h) => !/a[çc]õe?/i.test(h));
  const idxIgnorar = [...tabela.querySelectorAll('thead th')]
    .map((th, i) => (/a[çc]õe?/i.test(th.textContent) ? i : -1))
    .filter((i) => i >= 0);
  const linhas = [...tabela.querySelectorAll('tbody tr')]
    .map((tr) => [...tr.querySelectorAll('td')]
      .filter((td, i) => !idxIgnorar.includes(i))
      .map((td) => td.textContent.trim()));
  if (!linhas.length) {
    toast('Nada para exportar (lista vazia).', 'erro');
    return;
  }
  baixarCsv(nome, ths, linhas);
}

function iniciar() {
  document.querySelectorAll('table[data-export]').forEach((tabela) => {
    const nome = tabela.getAttribute('data-export');
    const bt = document.createElement('button');
    bt.type = 'button';
    bt.className = 'btn mini ghost';
    bt.textContent = '↓ Exportar CSV';
    bt.title = 'Baixar a lista atual em CSV (Excel/Google Sheets)';
    bt.style.cssText = 'display:block; margin:0 0 0.5rem auto;';
    bt.addEventListener('click', () => exportarTabela(tabela, nome));
    tabela.parentElement.insertBefore(bt, tabela);
  });
}

iniciar();