-- ============================================================
-- ETAPA 5 - FINANCEIRO
-- Executar no Supabase > SQL Editor
-- ============================================================

-- 1. Índices únicos para impedir cobrança duplicada
CREATE UNIQUE INDEX IF NOT EXISTS uq_financeiro_mensalidade
  ON public.financeiro (matricula_id, competencia, tipo)
  WHERE tipo = 'mensalidade';

CREATE UNIQUE INDEX IF NOT EXISTS uq_financeiro_avulsa
  ON public.financeiro (conteudo_id)
  WHERE tipo = 'aula_avulsa';

-- 2. Geração de mensalidades (RF23 / RN01)
--    Gera cobrança mensal para toda matrícula ATIVA de tipo mensal
--    do mês de início dela até "mes_final", sem duplicar.
--    Também marca atrasadas (pendente + vencimento < hoje).
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
      'Mensalidade - ' || COALESCE(t.nome, 'Aula individual'),
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

GRANT EXECUTE ON FUNCTION public.gerar_mensalidades(date) TO authenticated;

-- 3. Geração automática de aula avulsa (RF24 / RN02)
--    Ao lançar aula em matrícula avulsa, cria cobrança no valor da aula.
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

-- 4. Ao excluir aula avulsa, cancela a cobrança (RN08: nunca apaga financeiro)
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