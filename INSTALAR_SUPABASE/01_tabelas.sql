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
