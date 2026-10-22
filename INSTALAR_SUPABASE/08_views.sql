-- BLOCO 8 - VIEWS DE RELATÓRIOS
-- ============================================================

-- IMPORTANTE (segurança): view não tem RLS, e a view é executada com os
-- privilégios do dono (postgres = superusuário), ou seja, ignora o RLS das
-- tabelas. No Supabase, `anon` tem SELECT por padrão em ALL TABLES, então
-- qualquer visitante conseguiria ler nomes de alunos, inadimplência e
-- financeiro. Por isso as 6 views recebem `security_invoker = true`
-- (PostgreSQL 15+): a consulta passa a respeitar o RLS de quem chamou, ou
-- seja, só o admin logado enxerga os relatórios.

-- Desempenho médio por turma ao longo do tempo (RF31)
CREATE OR REPLACE VIEW public.vw_desempenho_turma AS
SELECT
  t.id AS turma_id,
  t.nome AS turma,
  cm.data_aula,
  ROUND(AVG(cm.evolucao_turma), 2) AS evolucao_media
FROM public.turmas t
JOIN public.conteudos_ministrados cm ON cm.turma_id = t.id
WHERE cm.evolucao_turma IS NOT NULL
GROUP BY t.id, t.nome, cm.data_aula
ORDER BY cm.data_aula;

-- Desempenho por aluno (RF32)
CREATE OR REPLACE VIEW public.vw_desempenho_aluno AS
SELECT
  a.id AS aluno_id,
  a.nome AS aluno,
  d.data,
  d.desempenho,
  cm.titulo AS aula_titulo,
  cm.turma_id
FROM public.desempenhos d
JOIN public.alunos a ON a.id = d.aluno_id
JOIN public.conteudos_ministrados cm ON cm.id = d.conteudo_id
ORDER BY d.data;

-- Resumo financeiro: previsto x recebido por competência (RF28/RF33)
CREATE OR REPLACE VIEW public.vw_financeiro_resumo AS
SELECT
  date_trunc('month', competencia) AS competencia,
  COALESCE(SUM(valor) FILTER (WHERE status IN ('pendente', 'atrasada')), 0) AS a_receber,
  COALESCE(SUM(valor) FILTER (WHERE status = 'paga'), 0)                   AS recebido,
  COALESCE(SUM(valor) FILTER (WHERE status = 'atrasada'), 0)               AS inadimplente
FROM public.financeiro
GROUP BY 1
ORDER BY 1;

-- Inadimplentes (RF34). Ajustes (descontos/créditos) não são inadimplência:
-- valor negativo em atraso não significa dívida.
CREATE OR REPLACE VIEW public.vw_inadimplentes AS
SELECT
  f.id AS lancamento_id,
  a.id AS aluno_id,
  a.nome AS aluno,
  f.descricao,
  f.valor,
  f.vencimento,
  CURRENT_DATE - f.vencimento AS dias_atraso
FROM public.financeiro f
JOIN public.alunos a ON a.id = f.aluno_id
WHERE f.status = 'pendente'
  AND f.vencimento < CURRENT_DATE
  AND f.tipo <> 'ajuste'
ORDER BY f.vencimento;

-- Progresso da grade POR TURMA (RF22)
CREATE OR REPLACE VIEW public.vw_progresso_turma AS
SELECT
  t.id   AS turma_id,
  t.nome AS turma,
  COUNT(g.id)                 AS total_itens,
  COUNT(DISTINCT cm.grade_id) AS ministrados,
  ROUND(
    100.0 * COUNT(DISTINCT cm.grade_id) / NULLIF(COUNT(g.id), 0), 1
  )                           AS percentual
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
  COUNT(g.id)                 AS total_itens,
  COUNT(DISTINCT cm.grade_id) AS ministrados,
  ROUND(
    100.0 * COUNT(DISTINCT cm.grade_id) / NULLIF(COUNT(g.id), 0), 1
  )                           AS percentual
FROM public.matriculas m
JOIN public.alunos a ON a.id = m.aluno_id
CROSS JOIN public.grade_conteudos g
LEFT JOIN public.conteudos_ministrados cm
  ON cm.grade_id = g.id AND cm.matricula_id = m.id
WHERE m.tipo = 'individual' AND g.ativo
GROUP BY m.id, a.id, a.nome;

-- Aplica o security_invoker em todas as views de public (PostgreSQL 15+).
-- A partir daqui, as views respeitam o RLS de quem consulta.
DO $$
DECLARE
  v TEXT;
BEGIN
  IF current_setting('server_version_num')::int >= 150000 THEN
    FOR v IN
      SELECT c.relname FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
       WHERE n.nspname = 'public' AND c.relkind = 'v'
    LOOP
      EXECUTE format('ALTER VIEW public.%I SET (security_invoker = true)', v);
    END LOOP;
    RAISE NOTICE 'Views com security_invoker = true: o RLS passa a valer para quem consulta.';
  ELSE
    RAISE WARNING 'PostgreSQL < 15: security_invoker indisponivel. As views seguem sem RLS — restrinja o SELECT com GRANT/REVOKE.';
  END IF;
END $$;


-- ============================================================
