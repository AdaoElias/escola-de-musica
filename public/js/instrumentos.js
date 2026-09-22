export const INSTRUMENTOS_BASE = [
  'Violão', 'Violão 7 cordas', 'Viola', 'Violoncelo', 'Violino', 'Contrabaixo', 'Baixo elétrico',
  'Guitarra', 'Teclado', 'Piano', 'Sintetizador', 'Órgão',
  'Bateria', 'Percussão', 'Cajon', 'Xilofone',
  'Flauta doce', 'Flauta transversal', 'Saxofone', 'Clarinete', 'Oboé', 'Fagote',
  'Trompete', 'Trombone', 'Tuba', 'Trompa', 'Euflônio',
  'Canto', 'Coral', 'Ukulele', 'Cavaquinho', 'Bandolim', 'Harpa', 'Gaita', 'Acordeon',
];

export const FORMACOES_BASE = [
  'Graduação em Música', 'Licenciatura em Música', 'Bacharelado em Música',
  'Técnico (Conservatório)', 'Pós-graduação em Música', 'Mestrado em Música',
  'Doutorado em Música', 'Musicoterapia', 'Curso livre', 'Autodidata',
];

export async function popularInstrumentos(sb) {
  const dl = document.getElementById('lista-instrumentos');
  if (!dl) return;
  const valores = new Set(INSTRUMENTOS_BASE);
  const { data } = await sb.from('professores').select('instrumento');
  for (const p of data || []) {
    if (p.instrumento && p.instrumento.trim()) valores.add(p.instrumento.trim());
  }
  dl.innerHTML = '';
  for (const v of [...valores].sort((a, b) => a.localeCompare(b, 'pt'))) {
    const op = document.createElement('option');
    op.value = v;
    dl.appendChild(op);
  }
}

export function popularFormacoes() {
  const dl = document.getElementById('lista-formacoes');
  if (!dl) return;
  dl.innerHTML = '';
  for (const f of FORMACOES_BASE) {
    const op = document.createElement('option');
    op.value = f;
    dl.appendChild(op);
  }
}