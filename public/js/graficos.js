function esc(s) {
  return String(s).replace(/[&<>"']/g, (c) => ({
    '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;',
  }[c]));
}

function largura(el) {
  return (el && el.clientWidth > 0) ? el.clientWidth : 640;
}

function grid(svg, w, h, ml, mr, mt, ih, botY, span, passos, fmt) {
  for (let g = 0; g <= passos; g++) {
    const val = botY + (span * g) / passos;
    const yy = mt + ih - ((val - botY) / span) * ih;
    svg += '<line x1="' + ml + '" y1="' + yy.toFixed(1) + '" x2="' + (w - mr) + '" y2="' + yy.toFixed(1) + '" class="g-reeb"/>';
    svg += '<text x="' + (ml - 6) + '" y="' + (yy + 3.5).toFixed(1) + '" text-anchor="end">' + fmt(val) + '</text>';
  }
  return svg;
}

export function linha(el, pontos, opts = {}) {
  if (!el) return;
  el.innerHTML = '';
  if (!pontos || !pontos.length) {
    el.innerHTML = '<p class="graf-vazio">Sem dados para exibir. Lance aulas e desempenhos para montar o gráfico.</p>';
    return;
  }
  const cor = opts.cor || 'var(--primaria)';
  const fmt = opts.fmt || String;
  const w = largura(el), h = 260;
  const ml = 54, mr = 16, mt = 16, mb = 30;
  const iw = w - ml - mr, ih = h - mt - mb;
  const vals = pontos.map((p) => Number(p.y));
  const maxY = Math.max(...vals);
  const minY = Math.min(...vals);
  const topY = maxY > 0 ? maxY : 1;
  const botY = minY >= 0 ? 0 : minY;
  const span = (topY - botY) || 1;
  const x = (i) => ml + (i / (pontos.length - 1 || 1)) * iw;
  const y = (v) => mt + ih - ((Number(v) - botY) / span) * ih;

  let svg = '<svg viewBox="0 0 ' + w + ' ' + h + '" class="grafico" role="img" aria-label="Gráfico de linhas">';
  svg = grid(svg, w, h, ml, mr, mt, ih, botY, span, 4, fmt);

  const passoX = Math.ceil(pontos.length / 6);
  pontos.forEach((p, i) => {
    if (i % passoX === 0 || i === pontos.length - 1) {
      svg += '<text x="' + x(i).toFixed(1) + '" y="' + (h - 8) + '" text-anchor="middle">' + esc(p.x) + '</text>';
    }
  });

  const d = pontos.map((p, i) =>
    (i ? 'L' : 'M') + x(i).toFixed(1) + ' ' + y(p.y).toFixed(1)).join(' ');
  if (opts.area !== false) {
    svg += '<path d="' + d + ' L ' + x(pontos.length - 1).toFixed(1) + ' ' + (mt + ih).toFixed(1) +
      ' L ' + ml + ' ' + (mt + ih).toFixed(1) + ' Z" fill="' + cor + '" opacity="0.12"/>';
  }
  svg += '<path d="' + d + '" fill="none" stroke="' + cor + '" stroke-width="2.5" stroke-linecap="round" stroke-linejoin="round"/>';
  pontos.forEach((p, i) => {
    svg += '<circle cx="' + x(i).toFixed(1) + '" cy="' + y(p.y).toFixed(1) + '" r="3.5" fill="var(--surface)" stroke="' + cor + '" stroke-width="2"/>';
  });
  svg += '</svg>';
  el.innerHTML = svg;
}

export function barras(el, cfg) {
  if (!el) return;
  el.innerHTML = '';
  const categorias = (cfg && cfg.categorias) || [];
  const series = (cfg && cfg.series) || [];
  if (!categorias.length || !series.length) {
    el.innerHTML = '<p class="graf-vazio">Sem dados para exibir.</p>';
    return;
  }
  const fmt = (cfg && cfg.fmt) || String;
  const w = largura(el), h = 300;
  const ml = 60, mr = 16, mt = 16, mb = 32;
  const iw = w - ml - mr, ih = h - mt - mb;
  const maxV = Math.max(...series.flatMap((s) => s.valores.map(Number)), 0);
  const topY = maxV > 0 ? maxV * 1.08 : 1;
  const groupW = iw / categorias.length;
  const serCount = series.length;
  const barW = Math.min((groupW * 0.66) / serCount, 42);

  let legend = '<div class="graf-legend">';
  const cores = ['var(--warning)', 'var(--ok)', 'var(--primaria)', 'var(--erro)'];
  const coresUsadas = series.map((s, j) => s.cor || cores[j % cores.length]);
  series.forEach((s, j) => {
    legend += '<span><i style="background:' + coresUsadas[j] + '"></i>' + esc(s.nome) + '</span>';
  });
  legend += '</div>';

  let svg = '<svg viewBox="0 0 ' + w + ' ' + h + '" class="grafico" role="img" aria-label="Gráfico de barras">';
  svg = grid(svg, w, h, ml, mr, mt, ih, 0, topY, 4, fmt);

  categorias.forEach((cat, i) => {
    svg += '<text x="' + (ml + i * groupW + groupW / 2).toFixed(1) + '" y="' + (h - 9) +
      '" text-anchor="middle">' + esc(cat) + '</text>';
    const totalW = barW * serCount;
    const inicio = ml + i * groupW + groupW / 2 - totalW / 2;
    series.forEach((s, j) => {
      const v = Number(s.valores[i] || 0);
      const hgt = (v / topY) * ih;
      const xx = inicio + j * barW;
      const yy = mt + ih - hgt;
      svg += '<rect x="' + xx.toFixed(1) + '" y="' + yy.toFixed(1) + '" width="' + (barW - 2).toFixed(1) +
        '" height="' + hgt.toFixed(1) + '" rx="3" fill="' + coresUsadas[j] + '"/>';
      if (v > 0) {
        svg += '<text x="' + (xx + (barW - 2) / 2).toFixed(1) + '" y="' + (yy - 5).toFixed(1) +
          '" text-anchor="middle">' + fmt(v) + '</text>';
      }
    });
  });
  svg += '</svg>';

  el.innerHTML = legend + svg;
}