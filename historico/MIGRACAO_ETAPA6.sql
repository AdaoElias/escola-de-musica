-- ============================================================
-- ETAPA 6 - MATRICULA + CARNE (parcelas 1/6/12) + RESPONSAVEL
-- Executar no Supabase > SQL Editor
-- ============================================================

-- 1. Novos valores de enum
ALTER TYPE tipo_pagamento  ADD VALUE IF NOT EXISTS 'parcelado';
ALTER TYPE tipo_lancamento ADD VALUE IF NOT EXISTS 'matricula';

-- 2. Novos campos em matriculas
--    tsx de matricula (paga no ato), valor do curso, parcelas 1/6/12,
--    dia fixo de vencimento e horario fixo (matricula individual / Aluno VIP)
ALTER TABLE public.matriculas
  ADD COLUMN IF NOT EXISTS valor_matricula          NUMERIC(10,2) NOT NULL DEFAULT 0,
  ADD COLUMN IF NOT EXISTS valor_total              NUMERIC(10,2),
  ADD COLUMN IF NOT EXISTS parcelas                 SMALLINT CHECK (parcelas IN (1, 6, 12)),
  ADD COLUMN IF NOT EXISTS dia_vencimento           SMALLINT NOT NULL DEFAULT 5 CHECK (dia_vencimento BETWEEN 1 AND 28),
  ADD COLUMN IF NOT EXISTS dia_semana               TEXT,
  ADD COLUMN IF NOT EXISTS horario                  TIME,
  ADD COLUMN IF NOT EXISTS matricula_forma_pagamento forma_pagamento NOT NULL DEFAULT 'pix';

-- 3. Dados do responsavel em alunos (obrigatorio p/ menor, RN-E)
ALTER TABLE public.alunos
  ADD COLUMN IF NOT EXISTS responsavel_nome      TEXT,
  ADD COLUMN IF NOT EXISTS responsavel_cpf       TEXT,
  ADD COLUMN IF NOT EXISTS responsavel_telefone  TEXT,
  ADD COLUMN IF NOT EXISTS parentesco            TEXT;  -- pai | mae | tutor | outro

-- 4. Indices unicos parciais (idempotente; tambem em MIGRACAO_ETAPA5)
CREATE UNIQUE INDEX IF NOT EXISTS uq_financeiro_mensalidade
  ON public.financeiro (matricula_id, competencia, tipo)
  WHERE tipo = 'mensalidade';

CREATE UNIQUE INDEX IF NOT EXISTS uq_financeiro_avulsa
  ON public.financeiro (conteudo_id)
  WHERE tipo = 'aula_avulsa';

-- 5. Trigger: matricula gera lancamento proprio PAGO NO ATO (RN-D)
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

-- 6. Geracao de mensalidades: ignora matricula parcelada (carnê cobre essas)
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
      (m + interval '1 month')::date - 1,
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

  UPDATE public.financeiro
     SET status = 'atrasada'
   WHERE status = 'pendente' AND vencimento < CURRENT_DATE;

  RETURN geradas;
END $$;

-- 7. Carnê: gera N parcelas (1/6/12) a partir do valor do curso (RN-C)
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

  SELECT * INTO mt FROM public.matriculas WHERE id = matricula_id;
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
    ON CONFLICT (matricula_id, competencia, tipo)
      WHERE tipo = 'mensalidade' DO NOTHING;
    GET DIAGNOSTICS n = ROW_COUNT;
    geradas := geradas + n;
  END LOOP;

  RETURN geradas;
END $$;

GRANT EXECUTE ON FUNCTION public.gerar_carne(bigint) TO authenticated;