-- ============================================================
-- Escola de Música - Schema Inicial (PostgreSQL / Supabase)
-- Executar em: Supabase > SQL Editor
-- ============================================================

-- ---------- Tipos enumerados ----------
CREATE TYPE perfil_usuario AS ENUM ('admin', 'professor');
CREATE TYPE tipo_matricula   AS ENUM ('turma', 'individual');
CREATE TYPE tipo_pagamento   AS ENUM ('mensal', 'avulsa', 'parcelado');
CREATE TYPE status_matricula AS ENUM ('ativa', 'trancada', 'concluida');
CREATE TYPE status_turma     AS ENUM ('ativa', 'encerrada');
CREATE TYPE tipo_lancamento  AS ENUM ('mensalidade', 'aula_avulsa', 'ajuste', 'matricula');
CREATE TYPE status_lancamento AS ENUM ('pendente', 'paga', 'atrasada', 'cancelada');
CREATE TYPE forma_pagamento  AS ENUM ('pix', 'cartao', 'dinheiro', 'boleto');

-- ---------- Tabelas ----------

-- Contas de acesso
CREATE TABLE usuarios (
  id          BIGSERIAL PRIMARY KEY,
  auth_uid    UUID UNIQUE,              -- id da conta no Supabase Auth
  nome        TEXT NOT NULL,
  email       TEXT NOT NULL UNIQUE,
  senha_hash  TEXT,                     -- gerenciado pelo Supabase Auth
  perfil      perfil_usuario NOT NULL DEFAULT 'professor',
  ativo       BOOLEAN NOT NULL DEFAULT true,
  criado_em   TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Cadastro de professores
CREATE TABLE professores (
  id          BIGSERIAL PRIMARY KEY,
  usuario_id  BIGINT REFERENCES usuarios(id) ON DELETE SET NULL,
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
CREATE TABLE alunos (
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
  -- Responsável legal (obrigatório quando aluno é menor de idade)
  responsavel_nome      TEXT,
  responsavel_cpf       TEXT,
  responsavel_telefone  TEXT,
  parentesco            TEXT    -- pai | mae | tutor | outro
);

-- Turmas coletivas
CREATE TABLE turmas (
  id            BIGSERIAL PRIMARY KEY,
  nome          TEXT NOT NULL,
  instrumento   TEXT,
  professor_id  BIGINT NOT NULL REFERENCES professores(id),
  dia_semana    TEXT,          -- ex.: 'segunda'
  horario       TIME,
  valor_mensal  NUMERIC(10,2) NOT NULL DEFAULT 0,
  status        status_turma NOT NULL DEFAULT 'ativa',
  criado_em     TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Matrículas: turma coletiva OU aula individual (tipo='individual' => turma_id NULL)
CREATE TABLE matriculas (
  id              BIGSERIAL PRIMARY KEY,
  aluno_id        BIGINT NOT NULL REFERENCES alunos(id) ON DELETE RESTRICT,
  turma_id        BIGINT REFERENCES turmas(id) ON DELETE RESTRICT,
  tipo            tipo_matricula NOT NULL DEFAULT 'turma',
  professor_id    BIGINT REFERENCES professores(id), -- exigido p/ individual
  tipo_pagamento  tipo_pagamento NOT NULL DEFAULT 'mensal',
  valor_mensal    NUMERIC(10,2) NOT NULL DEFAULT 0,  -- usado quando mensal
  valor_aula      NUMERIC(10,2) NOT NULL DEFAULT 0,  -- usado quando avulsa
  status          status_matricula NOT NULL DEFAULT 'ativa',
  data_inicio     DATE NOT NULL DEFAULT CURRENT_DATE,
  data_fim        DATE,
  observacao      TEXT,
  criado_em       TIMESTAMPTZ NOT NULL DEFAULT now(),
  -- Carnê (parcelado): taxa paga no ato, valor do curso e 1/6/12 parcelas
  valor_matricula             NUMERIC(10,2) NOT NULL DEFAULT 0,
  valor_total                 NUMERIC(10,2),
  parcelas                    SMALLINT CHECK (parcelas IN (1, 6, 12)),
  dia_vencimento              SMALLINT NOT NULL DEFAULT 5 CHECK (dia_vencimento BETWEEN 1 AND 28),
  matricula_forma_pagamento   forma_pagamento NOT NULL DEFAULT 'pix',
  -- Horário fixo (individual / Aluno VIP)
  dia_semana                  TEXT,
  horario                     TIME,
  CHECK (
    (tipo = 'turma' AND turma_id IS NOT NULL) OR
    (tipo = 'individual' AND turma_id IS NULL)
  ),
  CHECK (
    (tipo = 'individual' AND professor_id IS NOT NULL) OR
    (tipo = 'turma' AND professor_id IS NULL)
  ),
  CHECK (tipo <> 'turma' OR tipo_pagamento::text IN ('mensal', 'parcelado')),
  UNIQUE (aluno_id, turma_id, tipo)
);

-- Grade padrão de conteúdos (única; turmas/individuais avançam no próprio ritmo)
CREATE TABLE grade_conteudos (
  id             BIGSERIAL PRIMARY KEY,
  titulo         TEXT NOT NULL,
  descricao      TEXT,
  modulo         TEXT,          -- ex.: 'Módulo 1 - Fundamentos'
  nivel          TEXT,          -- ex.: 'Iniciante'
  ordem          INTEGER NOT NULL DEFAULT 0,
  tempo_estimado INTERVAL,
  ativo          BOOLEAN NOT NULL DEFAULT true,
  criado_em      TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Aulas/conteúdos ministrados (turma coletiva OU aluno individual)
CREATE TABLE conteudos_ministrados (
  id              BIGSERIAL PRIMARY KEY,
  turma_id        BIGINT REFERENCES turmas(id) ON DELETE CASCADE,
  matricula_id    BIGINT REFERENCES matriculas(id) ON DELETE CASCADE, -- p/ individual
  professor_id    BIGINT NOT NULL REFERENCES professores(id),
  grade_id        BIGINT REFERENCES grade_conteudos(id) ON DELETE SET NULL,
  data_aula       DATE NOT NULL DEFAULT CURRENT_DATE,
  titulo          TEXT,
  descricao       TEXT,
  evolucao_turma  NUMERIC(5,2) CHECK (evolucao_turma BETWEEN 0 AND 100), -- %
  observacoes     TEXT,
  criado_em       TIMESTAMPTZ NOT NULL DEFAULT now(),
  CHECK (turma_id IS NOT NULL OR matricula_id IS NOT NULL)
);

-- Desempenho individual por aula (base do gráfico por aluno mesmo dentro da turma)
CREATE TABLE desempenhos (
  id          BIGSERIAL PRIMARY KEY,
  aluno_id    BIGINT NOT NULL REFERENCES alunos(id) ON DELETE CASCADE,
  conteudo_id BIGINT NOT NULL REFERENCES conteudos_ministrados(id) ON DELETE CASCADE,
  desempenho  NUMERIC(5,2) NOT NULL CHECK (desempenho BETWEEN 0 AND 100),
  avaliacao   TEXT,
  data        DATE NOT NULL DEFAULT CURRENT_DATE,
  UNIQUE (aluno_id, conteudo_id)
);

-- Lançamentos financeiros (a receber = pendente/atrasada; recebido = paga)
CREATE TABLE financeiro (
  id              BIGSERIAL PRIMARY KEY,
  aluno_id        BIGINT NOT NULL REFERENCES alunos(id) ON DELETE RESTRICT,
  matricula_id    BIGINT REFERENCES matriculas(id) ON DELETE SET NULL,
  conteudo_id     BIGINT REFERENCES conteudos_ministrados(id) ON DELETE SET NULL, -- origem p/ aula_avulsa
  tipo            tipo_lancamento NOT NULL,
  descricao       TEXT NOT NULL,
  valor           NUMERIC(10,2) NOT NULL CHECK (valor >= 0),
  vencimento      DATE NOT NULL,
  competencia     DATE NOT NULL,        -- mês de referência (ex.: 2026-09-01)
  status          status_lancamento NOT NULL DEFAULT 'pendente',
  data_pagamento  DATE,
  forma_pagamento forma_pagamento,
  criado_em       TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- ---------- Índices ----------
CREATE INDEX idx_professores_usuario   ON professores(usuario_id);
CREATE INDEX idx_turmas_professor      ON turmas(professor_id);
CREATE INDEX idx_matriculas_aluno      ON matriculas(aluno_id);
CREATE INDEX idx_matriculas_turma      ON matriculas(turma_id);
CREATE INDEX idx_cm_turma              ON conteudos_ministrados(turma_id);
CREATE INDEX idx_cm_matricula          ON conteudos_ministrados(matricula_id);
CREATE INDEX idx_cm_data               ON conteudos_ministrados(data_aula);
CREATE INDEX idx_desempenhos_aluno     ON desempenhos(aluno_id);
CREATE INDEX idx_financeiro_aluno      ON financeiro(aluno_id);
CREATE INDEX idx_financeiro_status     ON financeiro(status);
CREATE INDEX idx_financeiro_vencimento ON financeiro(vencimento);
CREATE INDEX idx_financeiro_competencia ON financeiro(competencia);

-- Unicidade financeiro (Etapa 5/6): 1 mensalidade por matrícula/mês; 1 lançamento por aula avulsa
CREATE UNIQUE INDEX uq_financeiro_mensalidade
  ON financeiro (matricula_id, competencia, tipo)
  WHERE tipo = 'mensalidade';
CREATE UNIQUE INDEX uq_financeiro_avulsa
  ON financeiro (conteudo_id)
  WHERE tipo = 'aula_avulsa';

-- ---------- Views de relatórios ----------

-- Desempenho médio por turma ao longo do tempo
CREATE OR REPLACE VIEW vw_desempenho_turma AS
SELECT
  t.id AS turma_id,
  t.nome AS turma,
  cm.data_aula,
  ROUND(AVG(cm.evolucao_turma), 2) AS evolucao_media
FROM turmas t
JOIN conteudos_ministrados cm ON cm.turma_id = t.id
WHERE cm.evolucao_turma IS NOT NULL
GROUP BY t.id, t.nome, cm.data_aula
ORDER BY cm.data_aula;

-- Desempenho por aluno (individual e/ou dentro da turma)
CREATE OR REPLACE VIEW vw_desempenho_aluno AS
SELECT
  a.id AS aluno_id,
  a.nome AS aluno,
  d.data,
  d.desempenho,
  cm.titulo AS aula_titulo,
  cm.turma_id
FROM desempenhos d
JOIN alunos a ON a.id = d.aluno_id
JOIN conteudos_ministrados cm ON cm.id = d.conteudo_id
ORDER BY d.data;

-- Resumo financeiro: previsto (pendente/atrasada) vs. recebido (paga), por competência
CREATE OR REPLACE VIEW vw_financeiro_resumo AS
SELECT
  date_trunc('month', competencia) AS competencia,
  COALESCE(SUM(valor) FILTER (WHERE status IN ('pendente', 'atrasada')), 0) AS a_receber,
  COALESCE(SUM(valor) FILTER (WHERE status = 'paga'), 0)                   AS recebido,
  COALESCE(SUM(valor) FILTER (WHERE status = 'atrasada'), 0)               AS inadimplente
FROM financeiro
GROUP BY 1
ORDER BY 1;

-- Inadimplentes (listagem para controle de cobrança)
CREATE OR REPLACE VIEW vw_inadimplentes AS
SELECT
  f.id AS lancamento_id,
  a.id AS aluno_id,
  a.nome AS aluno,
  f.descricao,
  f.valor,
  f.vencimento,
  CURRENT_DATE - f.vencimento AS dias_atraso
FROM financeiro f
JOIN alunos a ON a.id = f.aluno_id
WHERE f.status = 'pendente'
  AND f.vencimento < CURRENT_DATE
ORDER BY f.vencimento;

-- ---------- Observação: RLS ----------
-- As políticas de segurança (Row Level Security) serão criadas
-- na Etapa 2, após o cadastro dos perfis admin/professor.
-- Regras previstas:
--   - Admin: acesso total a todas as tabelas.
--   - Professor: CRUD em conteudos_ministrados/desempenhos das
--     suas turmas e matrículas; leitura de alunos/turmas próprios;
--     sem acesso à tabela financeiro.