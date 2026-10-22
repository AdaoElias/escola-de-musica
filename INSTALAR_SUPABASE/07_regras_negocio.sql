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
