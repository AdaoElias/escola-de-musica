-- BLOCO 3 - CONSTRAINTS (nomes explícitos e determinísticos)
-- ============================================================

-- 3.1 Usuários: auth_uid único (o legado pode se chamar usuarios_auth_uid_key)
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint c
    JOIN pg_class t ON t.oid = c.conrelid
    JOIN pg_namespace n ON n.oid = t.relnamespace
    WHERE n.nspname = 'public' AND t.relname = 'usuarios' AND c.contype = 'u'
      AND (SELECT array_agg(a.attname::text ORDER BY a.attname::text)
             FROM unnest(c.conkey) k JOIN pg_attribute a ON a.attrelid = t.oid AND a.attnum = k)
          = ARRAY['auth_uid']
  ) THEN
    CREATE UNIQUE INDEX IF NOT EXISTS uq_usuarios_auth_uid ON public.usuarios (auth_uid);
  END IF;
END $$;

-- 3.2 senha_hash pode ser nulo (a senha é gerenciada pelo Supabase Auth)
ALTER TABLE public.usuarios ALTER COLUMN senha_hash DROP NOT NULL;

-- 3.3 Matrículas: turma sempre com turma_id; individual sempre sem turma_id
ALTER TABLE public.matriculas DROP CONSTRAINT IF EXISTS matriculas_check_turma;
ALTER TABLE public.matriculas ADD CONSTRAINT matriculas_check_turma CHECK (
  (tipo = 'turma' AND turma_id IS NOT NULL) OR
  (tipo = 'individual' AND turma_id IS NULL)
);

-- 3.4 Matrículas: individual sempre com professor_id; turma nunca com professor_id
ALTER TABLE public.matriculas DROP CONSTRAINT IF EXISTS matriculas_check_professor;
ALTER TABLE public.matriculas ADD CONSTRAINT matriculas_check_professor CHECK (
  (tipo = 'individual' AND professor_id IS NOT NULL) OR
  (tipo = 'turma' AND professor_id IS NULL)
);

-- 3.5 Matrículas: turma aceita somente mensal ou parcelado (avulsa é só individual)
ALTER TABLE public.matriculas DROP CONSTRAINT IF EXISTS matriculas_check_pagamento;
ALTER TABLE public.matriculas ADD CONSTRAINT matriculas_check_pagamento CHECK (
  tipo <> 'turma' OR tipo_pagamento::text IN ('mensal', 'parcelado')
);

-- 3.6 Matrículas: parcelas 1/6/12 e vencimento entre 1 e 28
ALTER TABLE public.matriculas DROP CONSTRAINT IF EXISTS matriculas_check_parcelas;
ALTER TABLE public.matriculas ADD CONSTRAINT matriculas_check_parcelas CHECK (
  parcelas IS NULL OR parcelas IN (1, 6, 12)
);

ALTER TABLE public.matriculas DROP CONSTRAINT IF EXISTS matriculas_check_dia_vencimento;
ALTER TABLE public.matriculas ADD CONSTRAINT matriculas_check_dia_vencimento CHECK (
  dia_vencimento BETWEEN 1 AND 28
);

-- 3.7 Matrículas: um aluno não pode ter a mesma turma/individual duplicado
--     (o UNIQUE antigo era UNIQUE(aluno_id, turma_id, tipo); em PostgreSQL NULL != NULL
--      em índice único, então ele NÃO protegeva as matrículas individuais —
--      a proteção real fica no índice parcial uq_matriculas_individual)
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint c
    JOIN pg_class t ON t.oid = c.conrelid
    JOIN pg_namespace n ON n.oid = t.relnamespace
    WHERE n.nspname = 'public' AND t.relname = 'matriculas' AND c.contype = 'u'
      AND (SELECT array_agg(a.attname::text ORDER BY a.attname::text)
             FROM unnest(c.conkey) k JOIN pg_attribute a ON a.attrelid = t.oid AND a.attnum = k)
          = ARRAY['aluno_id', 'tipo', 'turma_id']
  ) THEN
    CREATE UNIQUE INDEX IF NOT EXISTS uq_matriculas_aluno_turma_tipo
      ON public.matriculas (aluno_id, turma_id, tipo);
  END IF;
END $$;

-- 3.8 Conteúdos: uma aula por aluno (upsert de desempenho)
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint c
    JOIN pg_class t ON t.oid = c.conrelid
    JOIN pg_namespace n ON n.oid = t.relnamespace
    WHERE n.nspname = 'public' AND t.relname = 'desempenhos' AND c.contype = 'u'
      AND (SELECT array_agg(a.attname::text ORDER BY a.attname::text)
             FROM unnest(c.conkey) k JOIN pg_attribute a ON a.attrelid = t.oid AND a.attnum = k)
          = ARRAY['aluno_id', 'conteudo_id']
  ) THEN
    CREATE UNIQUE INDEX IF NOT EXISTS uq_desempenhos_aluno_conteudo
      ON public.desempenhos (aluno_id, conteudo_id);
  END IF;
END $$;

-- 3.9 Faixas numéricas
ALTER TABLE public.conteudos_ministrados DROP CONSTRAINT IF EXISTS conteudos_ministrados_check_evolucao;
ALTER TABLE public.conteudos_ministrados ADD CONSTRAINT conteudos_ministrados_check_evolucao
  CHECK (evolucao_turma IS NULL OR evolucao_turma BETWEEN 0 AND 100);

ALTER TABLE public.desempenhos DROP CONSTRAINT IF EXISTS desempenhos_check_desempenho;
ALTER TABLE public.desempenhos ADD CONSTRAINT desempenhos_check_desempenho
  CHECK (desempenho BETWEEN 0 AND 100);

-- 3.10 Aula sempre vinculada a turma OU a matrícula individual
ALTER TABLE public.conteudos_ministrados DROP CONSTRAINT IF EXISTS conteudos_ministrados_check_vinculo;
ALTER TABLE public.conteudos_ministrados ADD CONSTRAINT conteudos_ministrados_check_vinculo
  CHECK (turma_id IS NOT NULL OR matricula_id IS NOT NULL);

-- 3.11 Lançamento financeiro: valor não negativo — EXCETO em 'ajuste',
--      que pode ser negativo para representar desconto/crédito (RF29).
ALTER TABLE public.financeiro DROP CONSTRAINT IF EXISTS financeiro_check_valor;
ALTER TABLE public.financeiro ADD CONSTRAINT financeiro_check_valor
  CHECK (valor >= 0 OR tipo = 'ajuste');

-- 3.12 Normalização: remove os CHECKS de nome automático criados pelas versões
--      antigas do schema (SCHEMA.sql original). As regras equivalentes acima,
--      com nome determinístico, ficam valendo — nada é afrouxado.
ALTER TABLE public.matriculas             DROP CONSTRAINT IF EXISTS matriculas_check;
ALTER TABLE public.matriculas             DROP CONSTRAINT IF EXISTS matriculas_check1;
ALTER TABLE public.matriculas             DROP CONSTRAINT IF EXISTS matriculas_check2;
ALTER TABLE public.matriculas             DROP CONSTRAINT IF EXISTS matriculas_parcelas_check;
ALTER TABLE public.matriculas             DROP CONSTRAINT IF EXISTS matriculas_dia_vencimento_check;
ALTER TABLE public.conteudos_ministrados  DROP CONSTRAINT IF EXISTS conteudos_ministrados_check;
ALTER TABLE public.conteudos_ministrados  DROP CONSTRAINT IF EXISTS conteudos_ministrados_evolucao_turma_check;
ALTER TABLE public.desempenhos             DROP CONSTRAINT IF EXISTS desempenhos_desempenho_check;
ALTER TABLE public.financeiro              DROP CONSTRAINT IF EXISTS financeiro_valor_check;

-- 3.13 CPF: validação dos dígitos verificadores
--      Função IMMUTABLE usada pelos CHECKs das tabelas.
--      Aceita o CPF com ou sem máscara; vazio/NULL é válido (CPF é opcional).
CREATE OR REPLACE FUNCTION public.cpf_valido(cpf_txt TEXT) RETURNS BOOLEAN
LANGUAGE plpgsql IMMUTABLE AS $$
DECLARE
  d    TEXT;
  soma INT;
  dv   INT;
BEGIN
  IF cpf_txt IS NULL OR btrim(cpf_txt) = '' THEN
    RETURN TRUE;
  END IF;

  d := regexp_replace(cpf_txt, '[^0-9]', '', 'g');
  IF length(d) <> 11 THEN
    RETURN FALSE;
  END IF;

  IF d ~ '^(\d)\1{10}$' THEN
    RETURN FALSE;                      -- 000.000.000-00, 111.111.111-11, ...
  END IF;

  soma := 0;
  FOR i IN 1..9 LOOP
    soma := soma + substr(d, i, 1)::INT * (11 - i);
  END LOOP;
  dv := (soma * 10) % 11;
  IF dv = 10 THEN dv := 0; END IF;
  IF dv <> substr(d, 10, 1)::INT THEN
    RETURN FALSE;
  END IF;

  soma := 0;
  FOR i IN 1..10 LOOP
    soma := soma + substr(d, i, 1)::INT * (12 - i);
  END LOOP;
  dv := (soma * 10) % 11;
  IF dv = 10 THEN dv := 0; END IF;

  RETURN dv = substr(d, 11, 1)::INT;
END;
$$;

-- CHECKs de CPF criados como NOT VALID: a regra vale para todo registro novo,
-- sem travar a instalação em bases legadas que já têm CPF preenchido errado.
ALTER TABLE public.professores DROP CONSTRAINT IF EXISTS professores_cpf_valido;
ALTER TABLE public.professores ADD CONSTRAINT professores_cpf_valido
  CHECK (public.cpf_valido(cpf)) NOT VALID;

ALTER TABLE public.alunos DROP CONSTRAINT IF EXISTS alunos_cpf_valido;
ALTER TABLE public.alunos ADD CONSTRAINT alunos_cpf_valido
  CHECK (public.cpf_valido(cpf)) NOT VALID;

ALTER TABLE public.alunos DROP CONSTRAINT IF EXISTS alunos_responsavel_cpf_valido;
ALTER TABLE public.alunos ADD CONSTRAINT alunos_responsavel_cpf_valido
  CHECK (public.cpf_valido(responsavel_cpf)) NOT VALID;

-- Valida os CHECKs quando não há registro legado inválido; senão avisa.
DO $$
DECLARE
  c         RECORD;
  invalidos INT;
  msg       TEXT;
BEGIN
  FOR c IN
    SELECT * FROM (VALUES
      ('professores', 'cpf',             'professores_cpf_valido'),
      ('alunos',      'cpf',             'alunos_cpf_valido'),
      ('alunos',      'responsavel_cpf', 'alunos_responsavel_cpf_valido')
    ) AS v(tabela, coluna, constraint_nome)
  LOOP
    EXECUTE format(
      'SELECT count(*) FROM public.%I WHERE %I IS NOT NULL AND NOT public.cpf_valido(%I)',
      c.tabela, c.coluna, c.coluna
    ) INTO invalidos;

    IF invalidos > 0 THEN
      msg := format(
        'CPF invalido em %I.%I (%s registro(s) legado(s)) - o CHECK vale para novos registros. Corrija com: SELECT * FROM public.%I WHERE %I IS NOT NULL AND NOT public.cpf_valido(%I);',
        c.tabela, c.coluna, invalidos, c.tabela, c.coluna, c.coluna);
      RAISE WARNING '%', msg;
    ELSE
      EXECUTE format('ALTER TABLE public.%I VALIDATE CONSTRAINT %I', c.tabela, c.constraint_nome);
    END IF;
  END LOOP;
END $$;


-- Tempo estimado da grade: a UI grava MINUTOS (ex.: 'PT30M'). A constraint
-- impede que uma escrita direta deixe o campo com valores absurdos (ex.: 7 dias).
ALTER TABLE public.grade_conteudos DROP CONSTRAINT IF EXISTS grade_conteudos_tempo_estimado_check;
ALTER TABLE public.grade_conteudos ADD CONSTRAINT grade_conteudos_tempo_estimado_check
  CHECK (tempo_estimado IS NULL
         OR (tempo_estimado > interval '0' AND tempo_estimado <= interval '12 hours')) NOT VALID;

DO $$
DECLARE
  invalidos INT;
BEGIN
  SELECT count(*) INTO invalidos
    FROM public.grade_conteudos
   WHERE tempo_estimado IS NOT NULL
     AND NOT (tempo_estimado > interval '0' AND tempo_estimado <= interval '12 hours');

  IF invalidos > 0 THEN
    RAISE WARNING 'tempo_estimado fora do intervalo (0 a 12h) em % registro(s) legado(s) de grade_conteudos - o CHECK vale para novos registros.', invalidos;
  ELSE
    ALTER TABLE public.grade_conteudos VALIDATE CONSTRAINT grade_conteudos_tempo_estimado_check;
  END IF;
END $$;


-- ============================================================
