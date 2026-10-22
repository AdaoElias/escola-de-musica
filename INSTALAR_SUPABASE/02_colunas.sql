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
