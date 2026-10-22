-- BLOCO 4 - ÍNDICES
-- ============================================================

CREATE INDEX IF NOT EXISTS idx_professores_usuario   ON public.professores (usuario_id);
CREATE INDEX IF NOT EXISTS idx_turmas_professor      ON public.turmas (professor_id);
CREATE INDEX IF NOT EXISTS idx_matriculas_aluno      ON public.matriculas (aluno_id);
CREATE INDEX IF NOT EXISTS idx_matriculas_turma      ON public.matriculas (turma_id);
CREATE INDEX IF NOT EXISTS idx_cm_turma              ON public.conteudos_ministrados (turma_id);
CREATE INDEX IF NOT EXISTS idx_cm_matricula          ON public.conteudos_ministrados (matricula_id);
CREATE INDEX IF NOT EXISTS idx_cm_data               ON public.conteudos_ministrados (data_aula);
CREATE INDEX IF NOT EXISTS idx_desempenhos_aluno     ON public.desempenhos (aluno_id);
CREATE INDEX IF NOT EXISTS idx_financeiro_aluno      ON public.financeiro (aluno_id);
CREATE INDEX IF NOT EXISTS idx_financeiro_status     ON public.financeiro (status);
CREATE INDEX IF NOT EXISTS idx_financeiro_vencimento ON public.financeiro (vencimento);
CREATE INDEX IF NOT EXISTS idx_financeiro_competencia ON public.financeiro (competencia);

-- Uniquidade do financeiro: 1 mensalidade por matrícula/mês, 1 lançamento por aula avulsa
CREATE UNIQUE INDEX IF NOT EXISTS uq_financeiro_mensalidade
  ON public.financeiro (matricula_id, competencia, tipo)
  WHERE tipo = 'mensalidade';

CREATE UNIQUE INDEX IF NOT EXISTS uq_financeiro_avulsa
  ON public.financeiro (conteudo_id)
  WHERE tipo = 'aula_avulsa';

-- Aluno não repete matrícula individual com o mesmo professor (turma_id IS NULL)
CREATE UNIQUE INDEX IF NOT EXISTS uq_matriculas_individual
  ON public.matriculas (aluno_id, professor_id)
  WHERE turma_id IS NULL;

-- CPF único por pessoa. O índice compara só os dígitos, para bloquear
-- 123.456.789-00 e 12345678900 como o mesmo CPF.
-- responsavel_cpf NÃO é único: o mesmo responsável pode ter vários filhos.
DO $do$
DECLARE
  duplicados TEXT;
BEGIN
  SELECT string_agg(d.tabela || ' → ' || d.cpf_dig || ' (' || d.qtd || 'x)', '; ' ORDER BY d.tabela, d.cpf_dig)
    INTO duplicados
  FROM (
    SELECT 'alunos' AS tabela, regexp_replace(cpf, '[^0-9]', '', 'g') AS cpf_dig, count(*) AS qtd
      FROM public.alunos
     WHERE cpf IS NOT NULL AND btrim(cpf) <> ''
     GROUP BY 1, 2 HAVING count(*) > 1
    UNION ALL
    SELECT 'professores', regexp_replace(cpf, '[^0-9]', '', 'g'), count(*)
      FROM public.professores
     WHERE cpf IS NOT NULL AND btrim(cpf) <> ''
     GROUP BY 1, 2 HAVING count(*) > 1
  ) d;

  IF duplicados IS NOT NULL THEN
    RAISE WARNING 'CPF duplicado (%): uq_alunos_cpf e uq_professores_cpf NAO foram criados. Resolva e rode o INSTALAR.sql de novo.', duplicados;
    RETURN;
  END IF;

  EXECUTE $q$
    CREATE UNIQUE INDEX IF NOT EXISTS uq_alunos_cpf
      ON public.alunos (regexp_replace(cpf, '[^0-9]', '', 'g'))
     WHERE cpf IS NOT NULL AND btrim(cpf) <> ''
  $q$;

  EXECUTE $q$
    CREATE UNIQUE INDEX IF NOT EXISTS uq_professores_cpf
      ON public.professores (regexp_replace(cpf, '[^0-9]', '', 'g'))
     WHERE cpf IS NOT NULL AND btrim(cpf) <> ''
  $q$;
END
$do$;


-- ============================================================
