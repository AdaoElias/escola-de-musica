-- ============================================================
-- ETAPA 4 - Grade + Aulas + Progresso
-- Executar no Supabase > SQL Editor.
-- OBS: tabelas grade_conteudos, conteudos_ministrados e
-- desempenhos já existem (SCHEMA.sql) e RLS já está ativo
-- (MIGRACAO_ETAPA2.sql). Aqui só criamos as views de progresso.
-- ============================================================

-- Progresso da grade POR TURMA (RF22: ministrado vs. falta)
CREATE OR REPLACE VIEW public.vw_progresso_turma AS
SELECT
  t.id   AS turma_id,
  t.nome AS turma,
  COUNT(g.id)                          AS total_itens,
  COUNT(DISTINCT cm.grade_id)          AS ministrados,
  ROUND(
    100.0 * COUNT(DISTINCT cm.grade_id) / NULLIF(COUNT(g.id), 0), 1
  )                                    AS percentual
FROM public.turmas t
CROSS JOIN public.grade_conteudos g
LEFT JOIN public.conteudos_ministrados cm
  ON cm.grade_id = g.id AND cm.turma_id = t.id
WHERE g.ativo
GROUP BY t.id, t.nome;

-- Progresso da grade POR MATRÍCULA INDIVIDUAL (RF22)
CREATE OR REPLACE VIEW public.vw_progresso_aluno AS
SELECT
  m.id          AS matricula_id,
  a.id          AS aluno_id,
  a.nome        AS aluno,
  COUNT(g.id)                         AS total_itens,
  COUNT(DISTINCT cm.grade_id)         AS ministrados,
  ROUND(
    100.0 * COUNT(DISTINCT cm.grade_id) / NULLIF(COUNT(g.id), 0), 1
  )                                   AS percentual
FROM public.matriculas m
JOIN public.alunos a ON a.id = m.aluno_id
CROSS JOIN public.grade_conteudos g
LEFT JOIN public.conteudos_ministrados cm
  ON cm.grade_id = g.id AND cm.matricula_id = m.id
WHERE m.tipo = 'individual' AND g.ativo
GROUP BY m.id, a.id, a.nome;

-- Dica: as views herdam RLS das tabelas base (security invoker),
-- então professor só vê as próprias turmas/alunos.