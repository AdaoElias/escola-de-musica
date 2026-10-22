-- Itens #11 (vencimento = dia_vencimento) e #15 (RPC gerar_carne corrigida).
-- Requer um admin de teste para as RPCs de negocio: no Supabase, auth.uid() vem
-- do JWT da requisicao; no mock, do GUC de sessao 'request.jwt.claim.sub'.
-- O GUC vale so nesta sessao (psql -f abre uma conexao por arquivo), entao os
-- testes seguintes continuam como "ninguem logado".
SET request.jwt.claim.sub = '11111111-1111-1111-1111-111111111111';

INSERT INTO public.usuarios (nome, email, perfil, ativo, auth_uid)
VALUES ('Admin Teste', 'admin@teste.local', 'admin', true, '11111111-1111-1111-1111-111111111111')
ON CONFLICT (email) DO NOTHING;

INSERT INTO public.alunos (nome) VALUES ('Aluno Teste #11') ON CONFLICT DO NOTHING;
INSERT INTO public.professores (nome, instrumento) VALUES ('Professor Teste #11', 'Violão') ON CONFLICT DO NOTHING;

INSERT INTO public.turmas (nome, instrumento, professor_id, valor_mensal, status)
SELECT 'Turma Teste #11', 'Violão', p.id, 200.00, 'ativa'
FROM public.professores p WHERE p.nome = 'Professor Teste #11'
  AND NOT EXISTS (SELECT 1 FROM public.turmas t WHERE t.nome = 'Turma Teste #11');

-- Matricula MENSAL com dia_vencimento = 10, iniciada 3 meses atras
INSERT INTO public.matriculas
  (aluno_id, turma_id, tipo, tipo_pagamento, valor_mensal, status, data_inicio, dia_vencimento)
SELECT a.id, t.id, 'turma', 'mensal', 200.00, 'ativa',
       (date_trunc('month', CURRENT_DATE) - interval '3 months')::date, 10
FROM public.alunos a, public.turmas t
WHERE a.nome = 'Aluno Teste #11' AND t.nome = 'Turma Teste #11'
  AND NOT EXISTS (SELECT 1 FROM public.matriculas m WHERE m.aluno_id = a.id AND m.turma_id = t.id);

-- Matricula PARCELADA (carne) de 6x com o mesmo dia_vencimento
INSERT INTO public.alunos (nome) VALUES ('Aluno Teste #11 Carne') ON CONFLICT DO NOTHING;
INSERT INTO public.matriculas
  (aluno_id, turma_id, tipo, tipo_pagamento, valor_total, parcelas, status, data_inicio, dia_vencimento)
SELECT a.id, t.id, 'turma', 'parcelado', 1200.00, 6, 'ativa',
       (date_trunc('month', CURRENT_DATE) - interval '3 months')::date, 10
FROM public.alunos a, public.turmas t
WHERE a.nome = 'Aluno Teste #11 Carne' AND t.nome = 'Turma Teste #11'
  AND NOT EXISTS (SELECT 1 FROM public.matriculas m WHERE m.aluno_id = a.id AND m.parcelas = 6);

-- Matricula INDIVIDUAL de 1000,00 em 6x (teste de arredondamento)
INSERT INTO public.alunos (nome) VALUES ('Aluno Arredondamento') ON CONFLICT DO NOTHING;
INSERT INTO public.professores (nome, instrumento) VALUES ('Professor Arredondamento', 'Canto') ON CONFLICT DO NOTHING;
INSERT INTO public.matriculas
  (aluno_id, turma_id, tipo, professor_id, tipo_pagamento, valor_total, parcelas, status, data_inicio, dia_vencimento)
SELECT a.id, NULL, 'individual', p.id, 'parcelado', 1000.00, 6, 'ativa',
       date_trunc('month', CURRENT_DATE)::date, 5
FROM public.alunos a, public.professores p
WHERE a.nome = 'Aluno Arredondamento' AND p.nome = 'Professor Arredondamento'
  AND NOT EXISTS (SELECT 1 FROM public.matriculas m WHERE m.aluno_id = a.id AND m.parcelas = 6);

DO $$
DECLARE
  mid       BIGINT;
  n         INTEGER;
  n2        INTEGER;
  soma      NUMERIC;
  esperado  NUMERIC;
  ultima    NUMERIC;
  venc      DATE;
BEGIN
  -- Gera o carne da matricula parcelada
  SELECT m.id INTO mid FROM public.matriculas m
    JOIN public.turmas t ON t.id = m.turma_id
    JOIN public.alunos a ON a.id = m.aluno_id
   WHERE a.nome = 'Aluno Teste #11 Carne' AND t.nome = 'Turma Teste #11' AND m.parcelas = 6;
  IF mid IS NULL THEN RAISE EXCEPTION 'FALHOU: matricula de teste do carne nao encontrada'; END IF;

  PERFORM public.gerar_carne(mid);

  -- #15: 6 parcelas
  SELECT count(*) INTO n FROM public.financeiro f
    JOIN public.alunos a ON a.id = f.aluno_id
   WHERE a.nome = 'Aluno Teste #11 Carne' AND f.matricula_id = mid;
  IF n <> 6 THEN RAISE EXCEPTION 'FALHOU: carne gerou % parcela(s), esperado 6', n; END IF;

  -- #15: idempotencia (rodar de novo nao duplica)
  PERFORM public.gerar_carne(mid);
  SELECT count(*) INTO n2 FROM public.financeiro f
    JOIN public.alunos a ON a.id = f.aluno_id
   WHERE a.nome = 'Aluno Teste #11 Carne' AND f.matricula_id = mid;
  IF n2 <> n THEN RAISE EXCEPTION 'FALHOU: gerar_carne nao e idempotente (% -> %)', n, n2; END IF;

  -- #11: vencimento do carne = dia_vencimento (10) do mes da competencia
  SELECT f.vencimento INTO venc FROM public.financeiro f
    JOIN public.alunos a ON a.id = f.aluno_id
   WHERE a.nome = 'Aluno Teste #11 Carne' AND f.matricula_id = mid
   ORDER BY f.competencia LIMIT 1;
  IF extract(day FROM venc) <> 10 THEN
    RAISE EXCEPTION 'FALHOU: carne venceu em %, esperado dia 10', venc;
  END IF;

  -- Soma das parcelas = valor_total
  SELECT sum(f.valor) INTO soma FROM public.financeiro f
    JOIN public.matriculas m ON m.id = f.matricula_id
    JOIN public.alunos a ON a.id = f.aluno_id
   WHERE a.nome = 'Aluno Teste #11 Carne' AND f.matricula_id = mid;
  SELECT valor_total INTO esperado FROM public.matriculas WHERE id = mid;
  IF round(soma, 2) <> round(esperado, 2) THEN
    RAISE EXCEPTION 'FALHOU: soma do carne % <> valor_total %', soma, esperado;
  END IF;

  -- Arredondamento: 1000,00 / 6 = 166,67 (a ultima absorve a diferenca)
  SELECT m.id INTO mid FROM public.matriculas m
    JOIN public.alunos a ON a.id = m.aluno_id
   WHERE a.nome = 'Aluno Arredondamento';
  IF mid IS NULL THEN RAISE EXCEPTION 'FALHOU: matricula de arredondamento nao encontrada'; END IF;

  PERFORM public.gerar_carne(mid);

  SELECT count(*) INTO n FROM public.financeiro f WHERE f.matricula_id = mid;
  IF n <> 6 THEN RAISE EXCEPTION 'FALHOU: arredondamento gerou % parcela(s), esperado 6', n; END IF;

  SELECT sum(valor) INTO soma FROM public.financeiro WHERE matricula_id = mid;
  IF round(soma, 2) <> 1000.00 THEN
    RAISE EXCEPTION 'FALHOU: soma do carne arredondado % <> 1000.00', soma;
  END IF;

  SELECT valor INTO ultima FROM public.financeiro WHERE matricula_id = mid
   ORDER BY competencia DESC LIMIT 1;
  IF ultima <> 166.65 THEN
    RAISE EXCEPTION 'FALHOU: ultima parcela % <> 166.65 (166,67 x 5 = 833,35)', ultima;
  END IF;

  -- #11: gerar_mensalidades respeita dia_vencimento da matricula
  PERFORM public.gerar_mensalidades();

  SELECT f.vencimento INTO venc FROM public.financeiro f
    JOIN public.alunos a ON a.id = f.aluno_id
    JOIN public.matriculas m ON m.id = f.matricula_id
   WHERE a.nome = 'Aluno Teste #11' AND m.tipo_pagamento = 'mensal'
     AND f.competencia = date_trunc('month', CURRENT_DATE)::date
   LIMIT 1;
  IF venc IS NULL THEN
    RAISE EXCEPTION 'FALHOU: mensalidade do mes atual nao foi gerada';
  END IF;
  IF extract(day FROM venc) <> 10 THEN
    RAISE EXCEPTION 'FALHOU: mensalidade venceu em %, esperado dia 10', venc;
  END IF;

  RAISE NOTICE 'Vencimento (#11) e carne (#15): ok';
END $$;
