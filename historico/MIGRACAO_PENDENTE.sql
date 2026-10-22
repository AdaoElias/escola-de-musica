-- ============================================================
-- MIGRAÇÕES PENDENTES (aplicar de uma vez no Supabase > SQL Editor)
-- Conteúdo: MIGRACAO_FIX_RLS.sql + MIGRACAO_ETAPA4.sql
-- Idempotente: pode rodar de novo sem duplicar.
-- ============================================================

-- ------------------------------------------------------------
-- 1) FIX RLS - "stack depth limit exceeded" ao salvar professor
-- ------------------------------------------------------------
-- Causa: as funções auxiliares consultam usuarios/professores e
-- essas consultas passam pelas políticas RLS das próprias tabelas,
-- que chamam as mesmas funções de novo (recursão infinita).
-- Solução: torná-las SECURITY DEFINER (rodam como dono das tabelas,
-- ignorando RLS) -> sem recursão. Continuam seguras: apenas
-- identificam o usuário atual com base no próprio auth.uid().

CREATE OR REPLACE FUNCTION public.usuario_atual() RETURNS bigint
LANGUAGE sql STABLE SECURITY DEFINER
SET search_path = public AS $$
  SELECT u.id FROM public.usuarios u WHERE u.auth_uid = auth.uid();
$$;

CREATE OR REPLACE FUNCTION public.administrador_atual() RETURNS boolean
LANGUAGE sql STABLE SECURITY DEFINER
SET search_path = public AS $$
  SELECT EXISTS (
    SELECT 1 FROM public.usuarios u
    WHERE u.auth_uid = auth.uid() AND u.perfil = 'admin'
  );
$$;

CREATE OR REPLACE FUNCTION public.professor_atual() RETURNS bigint
LANGUAGE sql STABLE SECURITY DEFINER
SET search_path = public AS $$
  SELECT p.id FROM public.professores p
  JOIN public.usuarios u ON u.id = p.usuario_id
  WHERE u.auth_uid = auth.uid();
$$;

-- ------------------------------------------------------------
-- 2) ETAPA 4 - Grade + Aulas + Progresso (views de progresso)
-- ------------------------------------------------------------

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

-- Fim das migrações pendentes.