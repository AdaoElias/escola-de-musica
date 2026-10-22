-- ============================================================
-- INSTALAR.sql - Escola de Música
-- Instalação COMPLETA e idempotente do banco.
-- ============================================================
-- COMO USAR
--   Base nova  : Supabase > SQL Editor > New query > colar tudo > Run.
--   Base velha : rode o BLOCO 0 (enums) e clique em Run; depois cole do
--                BLOCO 1 em diante e clique em Run novamente.
--                (o Bloco 0 só é separado porque o Postgres não aceita
--                 usar um valor de enum recém-adicionado na mesma transação)
--
--   Para ir por partes: o mesmo script está dividido em 11 arquivos prontos
--   para colar, em INSTALAR_SUPABASE/ (guia em INSTALAR_SUPABASE/README.md).
--
-- IDEMPOTÊNCIA
--   Pode ser executado quantas vezes quiser: nada é duplicado, nada quebra.
--   Tabelas usam CREATE TABLE IF NOT EXISTS; colunas, ADD COLUMN IF NOT EXISTS;
--   constraints e policies são recriados com DROP ... IF EXISTS + CREATE;
--   funções e views usam CREATE OR REPLACE; triggers usam DROP ... IF EXISTS.
--
-- CONTEÚDO (= estado final do banco)
--   0) Enums
--   1) Tabelas
--   2) Colunas adicionadas depois (idempotente)
--   3) Constraints nomeadas
--   4) Índices
--   5) Funções auxiliares de RLS (SECURITY DEFINER)
--   6) RLS + políticas
--   7) Regras de negócio: RPCs e triggers de financeiro
--   8) Views de relatórios
--   9) Grants
--  10) Checagem final
-- ============================================================


-- ============================================================
-- BLOCO 0 - ENUMS
-- ============================================================
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_type t JOIN pg_namespace n ON n.oid = t.typnamespace
                 WHERE t.typname = 'perfil_usuario' AND n.nspname = 'public') THEN
    CREATE TYPE public.perfil_usuario AS ENUM ('admin', 'professor');
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_type t JOIN pg_namespace n ON n.oid = t.typnamespace
                 WHERE t.typname = 'tipo_matricula' AND n.nspname = 'public') THEN
    CREATE TYPE public.tipo_matricula AS ENUM ('turma', 'individual');
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_type t JOIN pg_namespace n ON n.oid = t.typnamespace
                 WHERE t.typname = 'tipo_pagamento' AND n.nspname = 'public') THEN
    CREATE TYPE public.tipo_pagamento AS ENUM ('mensal', 'avulsa', 'parcelado');
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_type t JOIN pg_namespace n ON n.oid = t.typnamespace
                 WHERE t.typname = 'status_matricula' AND n.nspname = 'public') THEN
    CREATE TYPE public.status_matricula AS ENUM ('ativa', 'trancada', 'concluida');
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_type t JOIN pg_namespace n ON n.oid = t.typnamespace
                 WHERE t.typname = 'status_turma' AND n.nspname = 'public') THEN
    CREATE TYPE public.status_turma AS ENUM ('ativa', 'encerrada');
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_type t JOIN pg_namespace n ON n.oid = t.typnamespace
                 WHERE t.typname = 'tipo_lancamento' AND n.nspname = 'public') THEN
    CREATE TYPE public.tipo_lancamento AS ENUM ('mensalidade', 'aula_avulsa', 'ajuste', 'matricula');
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_type t JOIN pg_namespace n ON n.oid = t.typnamespace
                 WHERE t.typname = 'status_lancamento' AND n.nspname = 'public') THEN
    CREATE TYPE public.status_lancamento AS ENUM ('pendente', 'paga', 'atrasada', 'cancelada');
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_type t JOIN pg_namespace n ON n.oid = t.typnamespace
                 WHERE t.typname = 'forma_pagamento' AND n.nspname = 'public') THEN
    CREATE TYPE public.forma_pagamento AS ENUM ('pix', 'cartao', 'dinheiro', 'boleto');
  END IF;
END $$;

-- Enums criados por versões antigas podem não ter estes valores:
ALTER TYPE public.tipo_pagamento  ADD VALUE IF NOT EXISTS 'parcelado';
ALTER TYPE public.tipo_lancamento ADD VALUE IF NOT EXISTS 'matricula';


-- ============================================================
-- BLOCO 1 - TABELAS
-- ============================================================

-- Contas de acesso (perfil e senha gerenciados pelo Supabase Auth)
CREATE TABLE IF NOT EXISTS public.usuarios (
  id          BIGSERIAL PRIMARY KEY,
  auth_uid    UUID UNIQUE,
  nome        TEXT NOT NULL,
  email       TEXT NOT NULL UNIQUE,
  senha_hash  TEXT,                     -- legado: senha é gerenciada pelo Supabase Auth
  perfil      public.perfil_usuario NOT NULL DEFAULT 'professor',
  ativo       BOOLEAN NOT NULL DEFAULT true,
  criado_em   TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Cadastro de professores
CREATE TABLE IF NOT EXISTS public.professores (
  id          BIGSERIAL PRIMARY KEY,
  usuario_id  BIGINT REFERENCES public.usuarios(id) ON DELETE SET NULL,
  nome        TEXT NOT NULL,
  cpf         TEXT,
  nascimento  DATE,
  instrumento TEXT,
  email       TEXT,
  telefone    TEXT,
  formacao    TEXT,
  endereco    TEXT,
  bairro      TEXT,
  cidade      TEXT,
  cep         TEXT,
  ativo       BOOLEAN NOT NULL DEFAULT true,
  criado_em   TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Cadastro de alunos
CREATE TABLE IF NOT EXISTS public.alunos (
  id          BIGSERIAL PRIMARY KEY,
  nome        TEXT NOT NULL,
  cpf         TEXT,
  nascimento  DATE,
  telefone    TEXT,
  email       TEXT,
  endereco    TEXT,
  bairro      TEXT,
  cidade      TEXT,
  cep         TEXT,
  observacao  TEXT,
  ativo       BOOLEAN NOT NULL DEFAULT true,
  criado_em   TIMESTAMPTZ NOT NULL DEFAULT now(),
  -- Responsável legal (obrigatório quando o aluno é menor de idade)
  responsavel_nome      TEXT,
  responsavel_cpf       TEXT,
  responsavel_telefone  TEXT,
  parentesco            TEXT      -- pai | mae | tutor | outro
);

-- Turmas coletivas
CREATE TABLE IF NOT EXISTS public.turmas (
  id            BIGSERIAL PRIMARY KEY,
  nome          TEXT NOT NULL,
  instrumento   TEXT,
  professor_id  BIGINT NOT NULL REFERENCES public.professores(id),
  dia_semana    TEXT,                  -- ex.: 'segunda'
  horario       TIME,
  valor_mensal  NUMERIC(10,2) NOT NULL DEFAULT 0,
  status        public.status_turma NOT NULL DEFAULT 'ativa',
  criado_em     TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Matrículas: turma coletiva OU aula individual
CREATE TABLE IF NOT EXISTS public.matriculas (
  id              BIGSERIAL PRIMARY KEY,
  aluno_id        BIGINT NOT NULL REFERENCES public.alunos(id) ON DELETE RESTRICT,
  turma_id        BIGINT REFERENCES public.turmas(id) ON DELETE RESTRICT,
  tipo            public.tipo_matricula NOT NULL DEFAULT 'turma',
  professor_id    BIGINT REFERENCES public.professores(id),   -- exigido p/ individual
  tipo_pagamento  public.tipo_pagamento NOT NULL DEFAULT 'mensal',
  valor_mensal    NUMERIC(10,2) NOT NULL DEFAULT 0,            -- usado quando mensal
  valor_aula      NUMERIC(10,2) NOT NULL DEFAULT 0,            -- usado quando avulsa
  status          public.status_matricula NOT NULL DEFAULT 'ativa',
  data_inicio     DATE NOT NULL DEFAULT CURRENT_DATE,
  data_fim        DATE,
  observacao      TEXT,
  criado_em       TIMESTAMPTZ NOT NULL DEFAULT now(),
  -- Carnê (parcelado): taxa paga no ato, valor do curso e 1/6/12 parcelas
  valor_matricula             NUMERIC(10,2) NOT NULL DEFAULT 0,
  valor_total                 NUMERIC(10,2),
  parcelas                    SMALLINT,
  dia_vencimento              SMALLINT NOT NULL DEFAULT 5,
  matricula_forma_pagamento   public.forma_pagamento NOT NULL DEFAULT 'pix',
  -- Horário fixo (individual / Aluno VIP)
  dia_semana                  TEXT,
  horario                     TIME
);

-- Grade padrão de conteúdos (única; turmas/individuais avançam no próprio ritmo)
CREATE TABLE IF NOT EXISTS public.grade_conteudos (
  id             BIGSERIAL PRIMARY KEY,
  titulo         TEXT NOT NULL,
  descricao      TEXT,
  modulo         TEXT,                -- ex.: 'Módulo 1 - Fundamentos'
  nivel          TEXT,                -- ex.: 'Iniciante'
  ordem          INTEGER NOT NULL DEFAULT 0,
  tempo_estimado INTERVAL,            -- ex.: '30 minutes'
  ativo          BOOLEAN NOT NULL DEFAULT true,
  criado_em      TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Aulas/conteúdos ministrados (turma coletiva OU aluno individual)
CREATE TABLE IF NOT EXISTS public.conteudos_ministrados (
  id              BIGSERIAL PRIMARY KEY,
  turma_id        BIGINT REFERENCES public.turmas(id) ON DELETE CASCADE,
  matricula_id    BIGINT REFERENCES public.matriculas(id) ON DELETE CASCADE, -- p/ individual
  professor_id    BIGINT NOT NULL REFERENCES public.professores(id),
  grade_id        BIGINT REFERENCES public.grade_conteudos(id) ON DELETE SET NULL,
  data_aula       DATE NOT NULL DEFAULT CURRENT_DATE,
  titulo          TEXT,
  descricao       TEXT,
  evolucao_turma  NUMERIC(5,2),       -- % (0-100)
  observacoes     TEXT,
  criado_em       TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Desempenho individual por aula (base do gráfico por aluno dentro da turma)
CREATE TABLE IF NOT EXISTS public.desempenhos (
  id          BIGSERIAL PRIMARY KEY,
  aluno_id    BIGINT NOT NULL REFERENCES public.alunos(id) ON DELETE CASCADE,
  conteudo_id BIGINT NOT NULL REFERENCES public.conteudos_ministrados(id) ON DELETE CASCADE,
  desempenho  NUMERIC(5,2) NOT NULL,
  avaliacao   TEXT,
  data        DATE NOT NULL DEFAULT CURRENT_DATE
);

-- Lançamentos financeiros (a receber = pendente/atrasada; recebido = paga)
CREATE TABLE IF NOT EXISTS public.financeiro (
  id              BIGSERIAL PRIMARY KEY,
  aluno_id        BIGINT NOT NULL REFERENCES public.alunos(id) ON DELETE RESTRICT,
  matricula_id    BIGINT REFERENCES public.matriculas(id) ON DELETE SET NULL,
  conteudo_id     BIGINT REFERENCES public.conteudos_ministrados(id) ON DELETE SET NULL,
  tipo            public.tipo_lancamento NOT NULL,
  descricao       TEXT NOT NULL,
  valor           NUMERIC(10,2) NOT NULL,
  vencimento      DATE NOT NULL,
  competencia     DATE NOT NULL,      -- mês de referência (ex.: 2026-09-01)
  status          public.status_lancamento NOT NULL DEFAULT 'pendente',
  data_pagamento  DATE,
  forma_pagamento public.forma_pagamento,
  criado_em       TIMESTAMPTZ NOT NULL DEFAULT now()
);


-- ============================================================
-- BLOCO 2 - COLUNAS ADICIONADAS DEPOIS (idempotente)
-- ============================================================

-- Só adiciona a coluna se ela ainda não existir (sem emitir "already exists").
DO $$
DECLARE
  r RECORD;
BEGIN
  FOR r IN
    SELECT * FROM (VALUES
      ('usuarios',    'auth_uid',                  'UUID'),
      ('professores', 'cpf',                       'TEXT'),
      ('professores', 'nascimento',                'DATE'),
      ('professores', 'endereco',                  'TEXT'),
      ('professores', 'bairro',                    'TEXT'),
      ('professores', 'cidade',                    'TEXT'),
      ('professores', 'cep',                       'TEXT'),
      ('alunos',      'cpf',                       'TEXT'),
      ('alunos',      'nascimento',                'DATE'),
      ('alunos',      'endereco',                  'TEXT'),
      ('alunos',      'bairro',                    'TEXT'),
      ('alunos',      'cidade',                    'TEXT'),
      ('alunos',      'cep',                       'TEXT'),
      ('alunos',      'responsavel_nome',          'TEXT'),
      ('alunos',      'responsavel_cpf',           'TEXT'),
      ('alunos',      'responsavel_telefone',      'TEXT'),
      ('alunos',      'parentesco',                'TEXT'),
      ('matriculas',  'valor_matricula',           'NUMERIC(10,2) NOT NULL DEFAULT 0'),
      ('matriculas',  'valor_total',               'NUMERIC(10,2)'),
      ('matriculas',  'parcelas',                  'SMALLINT'),
      ('matriculas',  'dia_vencimento',            'SMALLINT NOT NULL DEFAULT 5'),
      ('matriculas',  'dia_semana',                'TEXT'),
      ('matriculas',  'horario',                   'TIME'),
      ('matriculas',  'matricula_forma_pagamento', 'public.forma_pagamento NOT NULL DEFAULT ''pix''')
    ) AS v(tabela, coluna, definicao)
  LOOP
    IF NOT EXISTS (
      SELECT 1 FROM information_schema.columns
      WHERE table_schema = 'public' AND table_name = r.tabela AND column_name = r.coluna
    ) THEN
      EXECUTE format('ALTER TABLE public.%I ADD COLUMN %I %s', r.tabela, r.coluna, r.definicao);
    END IF;
  END LOOP;
END $$;


-- ============================================================
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
-- BLOCO 5 - FUNÇÕES AUXILIARES DE RLS
-- SECURITY DEFINER: sem isso, a policy da própria tabela chama a função
-- de novo (recursão) e o PostgreSQL estoura "stack depth limit exceeded".
-- ============================================================

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

-- Health check (acessível publicamente, sem expor dados)
CREATE OR REPLACE FUNCTION public.health_check() RETURNS text
LANGUAGE sql SECURITY DEFINER AS $$ SELECT 'ok'::text; $$;
GRANT EXECUTE ON FUNCTION public.health_check() TO anon, authenticated;


-- ============================================================
-- BLOCO 6 - RLS E POLÍTICAS
-- ============================================================

-- 6.1 Habilitar RLS em todas as tabelas
ALTER TABLE public.usuarios               ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.professores            ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.alunos                 ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.turmas                 ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.matriculas             ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.grade_conteudos        ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.conteudos_ministrados  ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.desempenhos            ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.financeiro             ENABLE ROW LEVEL SECURITY;

-- 6.2 USUARIOS (usuário vê a si; admin gerencia)
DROP POLICY IF EXISTS usuarios_select_self   ON public.usuarios;
DROP POLICY IF EXISTS usuarios_admin_select  ON public.usuarios;
DROP POLICY IF EXISTS usuarios_admin_insert  ON public.usuarios;
DROP POLICY IF EXISTS usuarios_admin_update  ON public.usuarios;
DROP POLICY IF EXISTS usuarios_admin_delete  ON public.usuarios;
CREATE POLICY usuarios_select_self      ON public.usuarios FOR SELECT USING (auth_uid = auth.uid());
CREATE POLICY usuarios_admin_select     ON public.usuarios FOR SELECT USING (public.administrador_atual());
CREATE POLICY usuarios_admin_insert     ON public.usuarios FOR INSERT WITH CHECK (public.administrador_atual());
CREATE POLICY usuarios_admin_update     ON public.usuarios FOR UPDATE USING (public.administrador_atual());
CREATE POLICY usuarios_admin_delete     ON public.usuarios FOR DELETE USING (public.administrador_atual());

-- 6.3 PROFESSORES (admin tudo; professor vê a si)
DROP POLICY IF EXISTS professores_select       ON public.professores;
DROP POLICY IF EXISTS professores_admin_insert ON public.professores;
DROP POLICY IF EXISTS professores_admin_update ON public.professores;
DROP POLICY IF EXISTS professores_admin_delete ON public.professores;
CREATE POLICY professores_select       ON public.professores FOR SELECT USING (public.administrador_atual() OR id = public.professor_atual());
CREATE POLICY professores_admin_insert ON public.professores FOR INSERT WITH CHECK (public.administrador_atual());
CREATE POLICY professores_admin_update ON public.professores FOR UPDATE USING (public.administrador_atual());
CREATE POLICY professores_admin_delete ON public.professores FOR DELETE USING (public.administrador_atual());

-- 6.4 TURMAS (admin tudo; professor vê as próprias)
DROP POLICY IF EXISTS turmas_select       ON public.turmas;
DROP POLICY IF EXISTS turmas_admin_insert ON public.turmas;
DROP POLICY IF EXISTS turmas_admin_update ON public.turmas;
DROP POLICY IF EXISTS turmas_admin_delete ON public.turmas;
CREATE POLICY turmas_select       ON public.turmas FOR SELECT USING (public.administrador_atual() OR professor_id = public.professor_atual());
CREATE POLICY turmas_admin_insert ON public.turmas FOR INSERT WITH CHECK (public.administrador_atual());
CREATE POLICY turmas_admin_update ON public.turmas FOR UPDATE USING (public.administrador_atual());
CREATE POLICY turmas_admin_delete ON public.turmas FOR DELETE USING (public.administrador_atual());

-- 6.5 ALUNOS (admin tudo; professor vê alunos vinculados às suas turmas/matrículas)
DROP POLICY IF EXISTS alunos_select       ON public.alunos;
DROP POLICY IF EXISTS alunos_admin_insert ON public.alunos;
DROP POLICY IF EXISTS alunos_admin_update ON public.alunos;
DROP POLICY IF EXISTS alunos_admin_delete ON public.alunos;
CREATE POLICY alunos_select       ON public.alunos FOR SELECT USING (
  public.administrador_atual() OR EXISTS (
    SELECT 1 FROM public.matriculas m
    WHERE m.aluno_id = alunos.id
      AND (m.professor_id = public.professor_atual()
        OR (SELECT t.professor_id FROM public.turmas t WHERE t.id = m.turma_id) = public.professor_atual())
  )
);
CREATE POLICY alunos_admin_insert ON public.alunos FOR INSERT WITH CHECK (public.administrador_atual());
CREATE POLICY alunos_admin_update ON public.alunos FOR UPDATE USING (public.administrador_atual());
CREATE POLICY alunos_admin_delete ON public.alunos FOR DELETE USING (public.administrador_atual());

-- 6.6 MATRÍCULAS
DROP POLICY IF EXISTS matriculas_select       ON public.matriculas;
DROP POLICY IF EXISTS matriculas_admin_insert ON public.matriculas;
DROP POLICY IF EXISTS matriculas_admin_update ON public.matriculas;
DROP POLICY IF EXISTS matriculas_admin_delete ON public.matriculas;
CREATE POLICY matriculas_select       ON public.matriculas FOR SELECT USING (
  public.administrador_atual() OR professor_id = public.professor_atual()
    OR (SELECT t.professor_id FROM public.turmas t WHERE t.id = matriculas.turma_id) = public.professor_atual()
);
CREATE POLICY matriculas_admin_insert ON public.matriculas FOR INSERT WITH CHECK (public.administrador_atual());
CREATE POLICY matriculas_admin_update ON public.matriculas FOR UPDATE USING (public.administrador_atual());
CREATE POLICY matriculas_admin_delete ON public.matriculas FOR DELETE USING (public.administrador_atual());

-- 6.7 GRADE_CONTEUDOS (qualquer usuário logado lê; admin edita)
DROP POLICY IF EXISTS grade_select       ON public.grade_conteudos;
DROP POLICY IF EXISTS grade_admin_insert ON public.grade_conteudos;
DROP POLICY IF EXISTS grade_admin_update ON public.grade_conteudos;
DROP POLICY IF EXISTS grade_admin_delete ON public.grade_conteudos;
CREATE POLICY grade_select       ON public.grade_conteudos FOR SELECT USING (auth.uid() IS NOT NULL);
CREATE POLICY grade_admin_insert ON public.grade_conteudos FOR INSERT WITH CHECK (public.administrador_atual());
CREATE POLICY grade_admin_update ON public.grade_conteudos FOR UPDATE USING (public.administrador_atual());
CREATE POLICY grade_admin_delete ON public.grade_conteudos FOR DELETE USING (public.administrador_atual());

-- 6.8 CONTEUDOS_MINISTRADOS (professor lança nas suas turmas/alunos)
DROP POLICY IF EXISTS cm_select ON public.conteudos_ministrados;
DROP POLICY IF EXISTS cm_insert ON public.conteudos_ministrados;
DROP POLICY IF EXISTS cm_update ON public.conteudos_ministrados;
DROP POLICY IF EXISTS cm_delete ON public.conteudos_ministrados;
CREATE POLICY cm_select ON public.conteudos_ministrados FOR SELECT USING (
  public.administrador_atual() OR professor_id = public.professor_atual()
    OR (SELECT t.professor_id FROM public.turmas t WHERE t.id = conteudos_ministrados.turma_id) = public.professor_atual()
    OR (SELECT m.professor_id FROM public.matriculas m WHERE m.id = conteudos_ministrados.matricula_id) = public.professor_atual()
);
CREATE POLICY cm_insert ON public.conteudos_ministrados FOR INSERT WITH CHECK (
  public.administrador_atual() OR professor_id = public.professor_atual()
    OR (SELECT t.professor_id FROM public.turmas t WHERE t.id = turma_id) = public.professor_atual()
    OR (SELECT m.professor_id FROM public.matriculas m WHERE m.id = matricula_id) = public.professor_atual()
);
CREATE POLICY cm_update ON public.conteudos_ministrados FOR UPDATE USING (
  public.administrador_atual() OR professor_id = public.professor_atual()
    OR (SELECT t.professor_id FROM public.turmas t WHERE t.id = conteudos_ministrados.turma_id) = public.professor_atual()
    OR (SELECT m.professor_id FROM public.matriculas m WHERE m.id = conteudos_ministrados.matricula_id) = public.professor_atual()
);
CREATE POLICY cm_delete ON public.conteudos_ministrados FOR DELETE USING (
  public.administrador_atual() OR professor_id = public.professor_atual()
    OR (SELECT t.professor_id FROM public.turmas t WHERE t.id = conteudos_ministrados.turma_id) = public.professor_atual()
    OR (SELECT m.professor_id FROM public.matriculas m WHERE m.id = conteudos_ministrados.matricula_id) = public.professor_atual()
);

-- 6.9 DESEMPENHOS (professor avalia apenas alunos que ensina)
DROP POLICY IF EXISTS desempenhos_select ON public.desempenhos;
DROP POLICY IF EXISTS desempenhos_insert ON public.desempenhos;
DROP POLICY IF EXISTS desempenhos_update ON public.desempenhos;
DROP POLICY IF EXISTS desempenhos_delete ON public.desempenhos;
CREATE POLICY desempenhos_select ON public.desempenhos FOR SELECT USING (
  public.administrador_atual() OR EXISTS (
    SELECT 1 FROM public.conteudos_ministrados cm
    WHERE cm.id = desempenhos.conteudo_id
      AND (cm.professor_id = public.professor_atual()
        OR (SELECT t.professor_id FROM public.turmas t WHERE t.id = cm.turma_id) = public.professor_atual()
        OR (SELECT m.professor_id FROM public.matriculas m WHERE m.id = cm.matricula_id) = public.professor_atual())
  )
);
CREATE POLICY desempenhos_insert ON public.desempenhos FOR INSERT WITH CHECK (
  public.administrador_atual() OR EXISTS (
    SELECT 1 FROM public.conteudos_ministrados cm
    WHERE cm.id = conteudo_id
      AND (cm.professor_id = public.professor_atual()
        OR (SELECT t.professor_id FROM public.turmas t WHERE t.id = cm.turma_id) = public.professor_atual()
        OR (SELECT m.professor_id FROM public.matriculas m WHERE m.id = cm.matricula_id) = public.professor_atual())
  )
);
CREATE POLICY desempenhos_update ON public.desempenhos FOR UPDATE USING (
  public.administrador_atual() OR EXISTS (
    SELECT 1 FROM public.conteudos_ministrados cm
    WHERE cm.id = desempenhos.conteudo_id
      AND (cm.professor_id = public.professor_atual()
        OR (SELECT t.professor_id FROM public.turmas t WHERE t.id = cm.turma_id) = public.professor_atual()
        OR (SELECT m.professor_id FROM public.matriculas m WHERE m.id = cm.matricula_id) = public.professor_atual())
  )
);
CREATE POLICY desempenhos_delete ON public.desempenhos FOR DELETE USING (
  public.administrador_atual() OR EXISTS (
    SELECT 1 FROM public.conteudos_ministrados cm
    WHERE cm.id = desempenhos.conteudo_id
      AND (cm.professor_id = public.professor_atual()
        OR (SELECT t.professor_id FROM public.turmas t WHERE t.id = cm.turma_id) = public.professor_atual()
        OR (SELECT m.professor_id FROM public.matriculas m WHERE m.id = cm.matricula_id) = public.professor_atual())
  )
);

-- 6.10 FINANCEIRO (exclusivo do Admin)
DROP POLICY IF EXISTS financeiro_admin_select ON public.financeiro;
DROP POLICY IF EXISTS financeiro_admin_insert ON public.financeiro;
DROP POLICY IF EXISTS financeiro_admin_update ON public.financeiro;
DROP POLICY IF EXISTS financeiro_admin_delete ON public.financeiro;
CREATE POLICY financeiro_admin_select ON public.financeiro FOR SELECT USING (public.administrador_atual());
CREATE POLICY financeiro_admin_insert ON public.financeiro FOR INSERT WITH CHECK (public.administrador_atual());
CREATE POLICY financeiro_admin_update ON public.financeiro FOR UPDATE USING (public.administrador_atual());
CREATE POLICY financeiro_admin_delete ON public.financeiro FOR DELETE USING (public.administrador_atual());


-- ============================================================
-- BLOCO 7 - REGRAS DE NEGÓCIO (RPCs e triggers)
-- ============================================================

-- 7.1 Mensalidades (RF23 / RN01): uma cobrança por matrícula ativa mensal,
--     do mês de início até mes_final. Ignora matrículas parceladas (o carnê cobre).
--     O vencimento é o dia_vencimento da matrícula dentro da competência —
--     mesma regra do carnê (7.7), para mensal e parcelado não divergirem.
CREATE OR REPLACE FUNCTION public.gerar_mensalidades(mes_final DATE DEFAULT CURRENT_DATE)
RETURNS INTEGER
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  geradas INTEGER := 0;
  n       INTEGER;
  primeiro DATE;
  m DATE;
BEGIN
  IF NOT public.administrador_atual() THEN
    RETURN 0;
  END IF;

  SELECT MIN(date_trunc('month', data_inicio)::date)
    INTO primeiro
    FROM public.matriculas
   WHERE status = 'ativa' AND tipo_pagamento = 'mensal';

  IF primeiro IS NULL THEN
    primeiro := date_trunc('month', CURRENT_DATE)::date;
  END IF;

  FOR m IN
    SELECT generate_series(primeiro, date_trunc('month', COALESCE(mes_final, CURRENT_DATE))::date, interval '1 month')::date
  LOOP
    INSERT INTO public.financeiro
      (aluno_id, matricula_id, tipo, descricao, valor, vencimento, competencia, status)
    SELECT
      mt.aluno_id,
      mt.id,
      'mensalidade',
      'Mensalidade - ' || COALESCE(t.nome, 'Aluno VIP'),
      COALESCE(t.valor_mensal, mt.valor_mensal, 0)::numeric(10,2),
      m + (mt.dia_vencimento - 1) * interval '1 day',
      m,
      'pendente'
    FROM public.matriculas mt
    LEFT JOIN public.turmas t ON t.id = mt.turma_id
    WHERE mt.status = 'ativa'
      AND mt.tipo_pagamento = 'mensal'
      AND date_trunc('month', mt.data_inicio)::date <= m
      AND NOT EXISTS (
        SELECT 1 FROM public.financeiro f
         WHERE f.matricula_id = mt.id
           AND f.tipo = 'mensalidade'
           AND f.competencia = m
      );
    GET DIAGNOSTICS n = ROW_COUNT;
    geradas := geradas + n;
  END LOOP;

  -- Marca em atraso o que está vencido. Crédito (ajuste negativo) não é atraso.
  UPDATE public.financeiro
     SET status = 'atrasada'
   WHERE status = 'pendente'
     AND vencimento < CURRENT_DATE
     AND (tipo <> 'ajuste' OR valor >= 0);

  RETURN geradas;
END $$;

GRANT EXECUTE ON FUNCTION public.gerar_mensalidades(date) TO authenticated;

-- 7.2 Aula avulsa (RF24 / RN02): lançar aula em matrícula avulsa cria a cobrança
CREATE OR REPLACE FUNCTION public.gerar_financeiro_avulsa()
RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public
AS $$
DECLARE mt public.matriculas%ROWTYPE;
BEGIN
  SELECT * INTO mt FROM public.matriculas WHERE id = NEW.matricula_id;
  IF FOUND AND mt.tipo_pagamento = 'avulsa' THEN
    INSERT INTO public.financeiro
      (aluno_id, matricula_id, conteudo_id, tipo, descricao, valor, vencimento, competencia, status)
    VALUES
      (mt.aluno_id, mt.id, NEW.id, 'aula_avulsa',
       'Aula avulsa - ' || COALESCE(NULLIF(NEW.titulo, ''), 'conteúdo livre'),
       mt.valor_aula::numeric(10,2),
       NEW.data_aula,
       date_trunc('month', NEW.data_aula)::date,
       'pendente')
    ON CONFLICT (conteudo_id) WHERE tipo = 'aula_avulsa' DO NOTHING;
  END IF;
  RETURN NEW;
END $$;

DROP TRIGGER IF EXISTS trig_financeiro_avulsa_insert ON public.conteudos_ministrados;
CREATE TRIGGER trig_financeiro_avulsa_insert
  AFTER INSERT ON public.conteudos_ministrados
  FOR EACH ROW WHEN (NEW.matricula_id IS NOT NULL)
  EXECUTE FUNCTION public.gerar_financeiro_avulsa();

-- 7.3 Excluir aula avulsa cancela a cobrança (RN08: nunca apaga financeiro)
CREATE OR REPLACE FUNCTION public.cancelar_financeiro_avulsa()
RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  UPDATE public.financeiro
     SET status = 'cancelada'
   WHERE conteudo_id = OLD.id
     AND tipo = 'aula_avulsa'
     AND status IN ('pendente', 'atrasada');
  RETURN OLD;
END $$;

DROP TRIGGER IF EXISTS trig_financeiro_avulsa_delete ON public.conteudos_ministrados;
CREATE TRIGGER trig_financeiro_avulsa_delete
  AFTER DELETE ON public.conteudos_ministrados
  FOR EACH ROW WHEN (OLD.matricula_id IS NOT NULL)
  EXECUTE FUNCTION public.cancelar_financeiro_avulsa();

-- 7.4 Matrícula gera lançamento próprio PAGO NO ATO (taxa de matrícula)
CREATE OR REPLACE FUNCTION public.gerar_financeiro_matricula()
RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF COALESCE(NEW.valor_matricula, 0) > 0 THEN
    INSERT INTO public.financeiro
      (aluno_id, matricula_id, tipo, descricao, valor, vencimento, competencia,
       status, data_pagamento, forma_pagamento)
    VALUES
      (NEW.aluno_id, NEW.id, 'matricula', 'Matrícula',
       NEW.valor_matricula, CURRENT_DATE, date_trunc('month', CURRENT_DATE)::date,
       'paga', CURRENT_DATE, COALESCE(NEW.matricula_forma_pagamento, 'pix'));
  END IF;
  RETURN NEW;
END $$;

DROP TRIGGER IF EXISTS trig_financeiro_matricula ON public.matriculas;
CREATE TRIGGER trig_financeiro_matricula
  AFTER INSERT ON public.matriculas
  FOR EACH ROW
  EXECUTE FUNCTION public.gerar_financeiro_matricula();

-- 7.5 Carnê (RF29/RN-C): gera N parcelas (1/6/12) a partir do valor do curso.
--     Bloqueia menor sem responsável; a última parcela absorve o arredondamento.
CREATE OR REPLACE FUNCTION public.gerar_carne(matricula_id BIGINT)
RETURNS INTEGER
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  mt     public.matriculas%ROWTYPE;
  al     public.alunos%ROWTYPE;
  t      public.turmas%ROWTYPE;
  qtd    INTEGER;
  inicio DATE;
  base   NUMERIC(10,2);
  parc   NUMERIC(10,2);
  n      INTEGER;
  i      INTEGER;
  comp   DATE;
  venci  DATE;
  curso  TEXT;
  geradas INTEGER := 0;
BEGIN
  IF NOT public.administrador_atual() THEN
    RETURN 0;
  END IF;

  -- O parâmetro chama a coluna de id: precisa ser qualificado, senão o
  -- PostgreSQL acusa "column reference is ambiguous" e o carnê nunca é gerado.
  SELECT * INTO mt FROM public.matriculas WHERE id = gerar_carne.matricula_id;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Matrícula não encontrada.';
  END IF;

  IF mt.tipo_pagamento <> 'parcelado' OR mt.parcelas IS NULL THEN
    RAISE EXCEPTION 'Matrícula não é parcelada (carnê).';
  END IF;

  IF COALESCE(mt.valor_total, 0) <= 0 THEN
    RAISE EXCEPTION 'Informe o valor do curso antes de gerar o carnê.';
  END IF;

  SELECT * INTO al FROM public.alunos WHERE id = mt.aluno_id;
  IF al.nascimento IS NOT NULL
     AND age(CURRENT_DATE, al.nascimento) < interval '18 years'
     AND (COALESCE(al.responsavel_nome, '') = '') THEN
    RAISE EXCEPTION 'Cadastre os dados do responsável (aluno menor de idade) antes de gerar o carnê.';
  END IF;

  IF mt.turma_id IS NOT NULL THEN
    SELECT * INTO t FROM public.turmas WHERE id = mt.turma_id;
    curso := COALESCE(t.nome, 'Turma');
  ELSE
    curso := 'Aluno VIP';
  END IF;

  qtd   := mt.parcelas;
  inicio := date_trunc('month', mt.data_inicio)::date;
  base  := round(mt.valor_total / qtd, 2);

  FOR i IN 0 .. qtd - 1 LOOP
    comp  := (inicio + make_interval(months => i))::date;
    venci := comp + (mt.dia_vencimento - 1) * interval '1 day';
    parc  := CASE WHEN i = qtd - 1 THEN mt.valor_total - (qtd - 1) * base ELSE base END;

    INSERT INTO public.financeiro
      (aluno_id, matricula_id, tipo, descricao, valor, vencimento, competencia, status)
    VALUES
      (mt.aluno_id, mt.id, 'mensalidade',
       'Parcela ' || (i + 1) || '/' || qtd || ' - ' || curso,
       parc, venci, comp, 'pendente')
    -- "ON CONFLICT DO NOTHING" sem alvo: nomear a coluna no conflito daria
    -- "column reference is ambiguous", porque o parâmetro da RPC também se
    -- chama matricula_id. O único conflito possível aqui é a mensalidade
    -- repetida (uq_financeiro_mensalidade).
    ON CONFLICT DO NOTHING;
    GET DIAGNOSTICS n = ROW_COUNT;
    geradas := geradas + n;
  END LOOP;

  RETURN geradas;
END $$;

GRANT EXECUTE ON FUNCTION public.gerar_carne(bigint) TO authenticated;


-- 7.6 Professor ativo: inativar exige que nao haja turma ativa (RN14)
--     Sem esta trava, turmas ficam orfas de professor e o painel so avisa
--     "turma sem aulas", mascarando a causa real.
CREATE OR REPLACE FUNCTION public.bloquear_inativacao_professor()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_turmas integer;
BEGIN
  IF NEW.ativo IS FALSE AND (TG_OP = 'INSERT' OR OLD.ativo IS NOT FALSE) THEN
    SELECT count(*) INTO v_turmas
      FROM public.turmas
     WHERE professor_id = NEW.id AND status = 'ativa';
    IF v_turmas > 0 THEN
      RAISE EXCEPTION
        'Professor tem % turma(s) ativa(s). Encerre ou transfira as turmas antes de inativar.',
        v_turmas
        USING ERRCODE = 'P0001';
    END IF;
  END IF;
  RETURN NEW;
END $$;

DROP TRIGGER IF EXISTS trig_professores_bloqueia_inativacao ON public.professores;
CREATE TRIGGER trig_professores_bloqueia_inativacao
  BEFORE UPDATE OF ativo ON public.professores
  FOR EACH ROW
  EXECUTE FUNCTION public.bloquear_inativacao_professor();


-- 7.7 Turma ativa exige professor ativo (RN14) - fecha o outro lado da regra:
--     professor so pode ser inativado sem turmas ativas, e turma so pode ser
--     ativada com professor ativo.
CREATE OR REPLACE FUNCTION public.exigir_professor_ativo_na_turma()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_ativo boolean;
BEGIN
  IF NEW.status = 'ativa' AND NEW.professor_id IS NOT NULL THEN
    SELECT ativo INTO v_ativo FROM public.professores WHERE id = NEW.professor_id;
    IF v_ativo IS FALSE THEN
      RAISE EXCEPTION
        'Turma ativa exige professor ativo. Transfira a turma ou mantenha a turma encerrada.'
        USING ERRCODE = 'P0001';
    END IF;
  END IF;
  RETURN NEW;
END $$;

DROP TRIGGER IF EXISTS trig_turmas_exige_professor_ativo ON public.turmas;
CREATE TRIGGER trig_turmas_exige_professor_ativo
  BEFORE INSERT OR UPDATE OF professor_id, status ON public.turmas
  FOR EACH ROW
  EXECUTE FUNCTION public.exigir_professor_ativo_na_turma();


-- ============================================================
-- BLOCO 8 - VIEWS DE RELATÓRIOS
-- ============================================================
-- IMPORTANTE (segurança): view não tem RLS, e a view é executada com os
-- privilégios do dono (postgres = superusuário), ou seja, ignora o RLS das
-- tabelas. No Supabase, `anon` tem SELECT por padrão em ALL TABLES, então
-- qualquer visitante conseguiria ler nomes de alunos, inadimplência e
-- financeiro. Por isso as 6 views são criadas com `security_invoker = true`
-- (PostgreSQL 15+): a consulta passa a respeitar o RLS de quem chamou, ou
-- seja, só o admin logado enxerga os relatórios.
DO $$
BEGIN
  IF current_setting('server_version_num')::int < 150000 THEN
    RAISE WARNING 'PostgreSQL < 15: security_invoker indisponivel. As views continuam sem RLS — restrinja o SELECT com GRANT/REVOKE.';
  END IF;
END $$;

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
-- BLOCO 9 - GRANTS
-- ============================================================

GRANT USAGE ON SCHEMA public TO anon, authenticated, service_role;
GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA public TO authenticated;
GRANT USAGE, SELECT ON ALL SEQUENCES IN SCHEMA public TO authenticated;

-- 9.1 Revogar o EXECUTE das funções de negócio para o visitante sem login.
--     ATENÇÃO: revogar de PUBLIC não basta no Supabase. O Supabase dá, por padrão,
--     `GRANT ALL ON ALL FUNCTIONS IN SCHEMA public TO anon, authenticated` E
--     `ALTER DEFAULT PRIVILEGES ... GRANT ALL ON FUNCTIONS TO anon` — ou seja, o
--     papel `anon` tem um privilégio EXPLICITO que sobrevive ao REVOKE ... FROM
--     PUBLIC. Por isso revogamos dos DOIS (PUBLIC e anon).
--     As RPCs já exigem `administrador_atual()`, mas o princípio do menor privilégio
--     vale: o `anon` não deve conseguir nem *chamar* a RPC.
REVOKE ALL ON FUNCTION public.cpf_valido(text) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.gerar_mensalidades(date) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.gerar_carne(bigint) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.gerar_financeiro_avulsa() FROM PUBLIC;
REVOKE ALL ON FUNCTION public.gerar_financeiro_matricula() FROM PUBLIC;
REVOKE ALL ON FUNCTION public.cancelar_financeiro_avulsa() FROM PUBLIC;
REVOKE ALL ON FUNCTION public.bloquear_inativacao_professor() FROM PUBLIC;
REVOKE ALL ON FUNCTION public.exigir_professor_ativo_na_turma() FROM PUBLIC;

REVOKE ALL ON FUNCTION public.cpf_valido(text) FROM anon;
REVOKE ALL ON FUNCTION public.gerar_mensalidades(date) FROM anon;
REVOKE ALL ON FUNCTION public.gerar_carne(bigint) FROM anon;
REVOKE ALL ON FUNCTION public.gerar_financeiro_avulsa() FROM anon;
REVOKE ALL ON FUNCTION public.gerar_financeiro_matricula() FROM anon;
REVOKE ALL ON FUNCTION public.cancelar_financeiro_avulsa() FROM anon;
REVOKE ALL ON FUNCTION public.bloquear_inativacao_professor() FROM anon;
REVOKE ALL ON FUNCTION public.exigir_professor_ativo_na_turma() FROM anon;

-- 9.2 Conceder EXECUTE apenas a quem está autenticado.
--     Inclui as funções de TRIGGER (disparadas por INSERT/UPDATE de quem está
--     logado): o papel que executa a ação precisa de EXECUTE nelas.
GRANT EXECUTE ON FUNCTION public.cpf_valido(text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.gerar_mensalidades(date) TO authenticated;
GRANT EXECUTE ON FUNCTION public.gerar_carne(bigint) TO authenticated;
GRANT EXECUTE ON FUNCTION public.gerar_financeiro_avulsa() TO authenticated;
GRANT EXECUTE ON FUNCTION public.gerar_financeiro_matricula() TO authenticated;
GRANT EXECUTE ON FUNCTION public.cancelar_financeiro_avulsa() TO authenticated;
GRANT EXECUTE ON FUNCTION public.bloquear_inativacao_professor() TO authenticated;
GRANT EXECUTE ON FUNCTION public.exigir_professor_ativo_na_turma() TO authenticated;

-- 9.3 As funções de RLS (usuario_atual, administrador_atual, professor_atual)
--     PRECISAM continuar executáveis por QUALQUER papel, inclusive `anon`:
--     são elas que as políticas de RLS chamam ao avaliar cada linha. Se o
--     papel que consulta não puder chamá-las, a consulta falha com "permissão
--     negada" em vez de devolver lista vazia. Elas são inofensivas para quem
--     não está logado (auth.uid() é NULL → devolvem NULL/false).
GRANT EXECUTE ON FUNCTION public.usuario_atual() TO anon, authenticated;
GRANT EXECUTE ON FUNCTION public.administrador_atual() TO anon, authenticated;
GRANT EXECUTE ON FUNCTION public.professor_atual() TO anon, authenticated;


-- ============================================================
-- BLOCO 10 - CHECAGEM FINAL (deve retornar 9 tabelas, 6 views, 12 funções)
-- ============================================================
SELECT
  (SELECT count(*) FROM pg_tables     WHERE schemaname = 'public' AND tablename IN
     ('usuarios','professores','alunos','turmas','matriculas','grade_conteudos',
      'conteudos_ministrados','desempenhos','financeiro'))      AS tabelas,
  (SELECT count(*) FROM pg_views      WHERE schemaname = 'public' AND viewname LIKE 'vw_%') AS views,
  (SELECT count(*) FROM pg_policies   WHERE schemaname = 'public') AS politicas,
  (SELECT count(*) FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
     WHERE n.nspname = 'public')                                 AS funcoes,
  (SELECT count(*) FROM pg_trigger t WHERE NOT t.tgisinternal)   AS triggers;
-- Resultado esperado: 9 tabelas | 6 views | 37 politicas | 12 funcoes | 5 triggers
