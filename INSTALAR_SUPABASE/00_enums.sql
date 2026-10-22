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
