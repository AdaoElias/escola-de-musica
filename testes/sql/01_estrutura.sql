-- Estrutura do banco: tabelas, views, funcoes, triggers, politicas, indices.
-- Rodar depois de INSTALAR.sql (com ou sem seed).
-- As assercoes de unicidade sao SEMANTICAS (nao por nome): em base legada o
-- indice pode ter outro nome, mas a regra precisa existir.
DO $$
DECLARE
  n          INTEGER;
  faltando   TEXT;
  colunas    TEXT[];
BEGIN
  SELECT string_agg(t, ', ' ORDER BY t) INTO faltando
  FROM unnest(ARRAY['usuarios','professores','alunos','turmas','matriculas',
                    'grade_conteudos','conteudos_ministrados','desempenhos','financeiro']) AS t
  WHERE NOT EXISTS (SELECT 1 FROM pg_tables WHERE schemaname='public' AND tablename=t);
  IF faltando IS NOT NULL THEN
    RAISE EXCEPTION 'FALHOU: tabela(s) ausente(s): %', faltando;
  END IF;

  SELECT count(*) INTO n FROM pg_views WHERE schemaname='public' AND viewname LIKE 'vw\_%';
  IF n <> 6 THEN RAISE EXCEPTION 'FALHOU: esperado 6 views, veio %', n; END IF;

  SELECT count(*) INTO n FROM pg_policies WHERE schemaname='public';
  IF n <> 37 THEN RAISE EXCEPTION 'FALHOU: esperado 37 politicas, veio %', n; END IF;

  SELECT count(*) INTO n FROM pg_trigger t WHERE NOT t.tgisinternal;
  IF n <> 5 THEN RAISE EXCEPTION 'FALHOU: esperado 5 triggers, veio %', n; END IF;

  -- Funcoes de negocio e de RLS
  SELECT count(*) INTO n FROM pg_proc p JOIN pg_namespace ns ON ns.oid=p.pronamespace
   WHERE ns.nspname='public'
     AND p.proname IN ('gerar_mensalidades','gerar_carne','gerar_financeiro_avulsa',
                       'gerar_financeiro_matricula','cpf_valido','usuario_atual',
                       'administrador_atual','professor_atual','health_check',
                       'bloquear_inativacao_professor','exigir_professor_ativo_na_turma');
  IF n <> 11 THEN RAISE EXCEPTION 'FALHOU: esperado 11 funcoes de negocio/RLS, veio %', n; END IF;

  -- Constraints nomeadas (deterministicas) exigidas pelas regras
  SELECT count(*) INTO n FROM pg_constraint WHERE conname IN
    ('financeiro_check_valor','professores_cpf_valido','alunos_cpf_valido',
     'alunos_responsavel_cpf_valido','grade_conteudos_tempo_estimado_check');
  IF n <> 5 THEN RAISE EXCEPTION 'FALHOU: esperado 5 constraints nomeadas, veio %', n; END IF;

  -- Unicidade semantica: 1 matricula por (aluno, turma, tipo)
  SELECT array_agg(a.attname ORDER BY k.ord) INTO colunas
    FROM pg_index x
    JOIN pg_class t ON t.oid = x.indrelid
    JOIN pg_namespace ns ON ns.oid = t.relnamespace
    CROSS JOIN LATERAL unnest(x.indkey) WITH ORDINALITY AS k(attnum, ord)
    JOIN pg_attribute a ON a.attrelid = t.oid AND a.attnum = k.attnum
   WHERE ns.nspname='public' AND t.relname='matriculas' AND x.indisunique
     AND x.indnatts = 3 AND x.indpred IS NULL;
  IF colunas IS DISTINCT FROM ARRAY['aluno_id','turma_id','tipo'] THEN
    RAISE EXCEPTION 'FALHOU: falta unicidade (aluno_id, turma_id, tipo) em matriculas';
  END IF;

  -- Unicidade semantica: 1 desempenho por (aluno, conteudo)
  SELECT array_agg(a.attname ORDER BY k.ord) INTO colunas
    FROM pg_index x
    JOIN pg_class t ON t.oid = x.indrelid
    JOIN pg_namespace ns ON ns.oid = t.relnamespace
    CROSS JOIN LATERAL unnest(x.indkey) WITH ORDINALITY AS k(attnum, ord)
    JOIN pg_attribute a ON a.attrelid = t.oid AND a.attnum = k.attnum
   WHERE ns.nspname='public' AND t.relname='desempenhos' AND x.indisunique
     AND x.indnatts = 2 AND x.indpred IS NULL;
  IF colunas IS DISTINCT FROM ARRAY['aluno_id','conteudo_id'] THEN
    RAISE EXCEPTION 'FALHOU: falta unicidade (aluno_id, conteudo_id) em desempenho';
  END IF;

  -- Matricula individual unica (aluno + professor, turma_id IS NULL)
  IF NOT EXISTS (SELECT 1 FROM pg_indexes WHERE schemaname='public' AND indexname='uq_matriculas_individual') THEN
    RAISE EXCEPTION 'FALHOU: indice uq_matriculas_individual ausente';
  END IF;

  -- 1 mensalidade por (matricula, competencia) e 1 avulsa por conteudo
  IF NOT EXISTS (
    SELECT 1 FROM pg_index x
      JOIN pg_class t ON t.oid = x.indrelid
      JOIN pg_namespace ns ON ns.oid = t.relnamespace
     WHERE ns.nspname='public' AND t.relname='financeiro' AND x.indisunique
       AND pg_get_indexdef(x.indexrelid) LIKE '%(matricula_id, competencia, tipo)%'
       AND pg_get_indexdef(x.indexrelid) LIKE $q$%tipo = 'mensalidade'%$q$
  ) THEN
    RAISE EXCEPTION 'FALHOU: falta unicidade da mensalidade em financeiro';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_index x
      JOIN pg_class t ON t.oid = x.indrelid
      JOIN pg_namespace ns ON ns.oid = t.relnamespace
     WHERE ns.nspname='public' AND t.relname='financeiro' AND x.indisunique
       AND pg_get_indexdef(x.indexrelid) LIKE '%(conteudo_id)%'
       AND pg_get_indexdef(x.indexrelid) LIKE $q$%tipo = 'aula_avulsa'%$q$
  ) THEN
    RAISE EXCEPTION 'FALHOU: falta unicidade da aula avulsa em financeiro';
  END IF;

  -- CPF unico por aluno e por professor. Os indices sao criados pelo INSTALAR.sql
  -- SO quando nao ha CPF duplicado no legado - nesse caso o script avisa e segue.
  SELECT count(*) INTO n FROM pg_indexes
   WHERE schemaname='public' AND indexname IN ('uq_alunos_cpf','uq_professores_cpf');
  IF n <> 2 THEN
    SELECT count(*) INTO n FROM (
      SELECT regexp_replace(cpf, '[^0-9]', '', 'g') AS dig, count(*)
        FROM public.alunos WHERE cpf IS NOT NULL AND btrim(cpf) <> '' GROUP BY 1 HAVING count(*) > 1
      UNION ALL
      SELECT regexp_replace(cpf, '[^0-9]', '', 'g'), count(*)
        FROM public.professores WHERE cpf IS NOT NULL AND btrim(cpf) <> '' GROUP BY 1 HAVING count(*) > 1
    ) d;
    IF n = 0 THEN
      RAISE EXCEPTION 'FALHOU: indices de CPF unico ausentes sem CPF duplicado no legado';
    END IF;
  END IF;

  -- Responsavel_cpf NAO pode ser unico (mesmo responsavel, varios filhos)
  IF EXISTS (SELECT 1 FROM pg_indexes WHERE schemaname='public' AND indexname LIKE '%responsavel%cpf%') THEN
    RAISE EXCEPTION 'FALHOU: responsavel_cpf nao pode ter indice unico';
  END IF;

  RAISE NOTICE 'Estrutura: ok';
END $$;
