-- Item #5 (desconto/crédito) e item #6 (CPF) - regras de negocio.
DO $$
DECLARE
  n INTEGER;
BEGIN
  -- #5 ajuste negativo deve ser aceito
  BEGIN
    INSERT INTO public.financeiro (aluno_id, tipo, descricao, valor, vencimento, competencia, status)
    SELECT id, 'ajuste', 'Desconto Teste', -50, CURRENT_DATE, date_trunc('month', CURRENT_DATE)::date, 'pendente'
      FROM public.alunos LIMIT 1;
  EXCEPTION WHEN OTHERS THEN
    RAISE EXCEPTION 'FALHOU: ajuste negativo nao aceito: %', SQLERRM;
  END;

  -- #5 mensalidade negativa deve ser bloqueada
  BEGIN
    INSERT INTO public.financeiro (aluno_id, tipo, descricao, valor, vencimento, competencia, status)
    SELECT id, 'mensalidade', 'X', -50, CURRENT_DATE, date_trunc('month', CURRENT_DATE)::date, 'pendente'
      FROM public.alunos LIMIT 1;
    RAISE EXCEPTION 'FALHOU: mensalidade negativa nao bloqueada';
  EXCEPTION WHEN check_violation THEN NULL;
  END;

  -- #5 aula avulsa negativa deve ser bloqueada
  BEGIN
    INSERT INTO public.financeiro (aluno_id, tipo, descricao, valor, vencimento, competencia, status)
    SELECT id, 'aula_avulsa', 'X', -50, CURRENT_DATE, date_trunc('month', CURRENT_DATE)::date, 'pendente'
      FROM public.alunos LIMIT 1;
    RAISE EXCEPTION 'FALHOU: aula avulsa negativa nao bloqueada';
  EXCEPTION WHEN check_violation THEN NULL;
  END;

  -- #5 ajuste nao entra na lista de inadimplentes
  SELECT count(*) INTO n FROM public.vw_inadimplentes WHERE descricao = 'Desconto Teste';
  IF n <> 0 THEN RAISE EXCEPTION 'FALHOU: ajuste negativo apareceu como inadimplente'; END IF;

  -- #5 ajuste negativo nao vira 'atrasada' na geracao de mensalidades
  IF EXISTS (SELECT 1 FROM public.financeiro WHERE descricao='Desconto Teste' AND status='atrasada') THEN
    RAISE EXCEPTION 'FALHOU: ajuste negativo marcado como atrasada';
  END IF;

  -- #6 CPF do seed e valido
  SELECT count(*) INTO n FROM public.alunos WHERE cpf IS NOT NULL AND NOT public.cpf_valido(cpf);
  IF n <> 0 THEN RAISE EXCEPTION 'FALHOU: % aluno(s) com CPF invalido no seed', n; END IF;
  SELECT count(*) INTO n FROM public.professores WHERE cpf IS NOT NULL AND NOT public.cpf_valido(cpf);
  IF n <> 0 THEN RAISE EXCEPTION 'FALHOU: % professor(es) com CPF invalido no seed', n; END IF;

  -- #6 CPF duplicado (mesma mascara) bloqueado
  BEGIN
    INSERT INTO public.alunos (nome, cpf)
    SELECT 'CPF Duplicado', cpf FROM public.alunos WHERE cpf IS NOT NULL LIMIT 1;
    RAISE EXCEPTION 'FALHOU: CPF duplicado nao bloqueado';
  EXCEPTION WHEN unique_violation THEN NULL;
  END;

  -- #6 CPF duplicado (mascara diferente) bloqueado
  BEGIN
    INSERT INTO public.alunos (nome, cpf)
    SELECT 'CPF Duplicado 2', regexp_replace(cpf, '[^0-9]', '', 'g')
      FROM public.alunos WHERE cpf IS NOT NULL LIMIT 1;
    RAISE EXCEPTION 'FALHOU: CPF duplicado (mascara diferente) nao bloqueado';
  EXCEPTION WHEN unique_violation THEN NULL;
  END;

  -- #6 CPF com digitos invalidos bloqueado
  BEGIN
    INSERT INTO public.alunos (nome, cpf) VALUES ('CPF Invalido', '123.456.789-00');
    RAISE EXCEPTION 'FALHOU: CPF invalido nao bloqueado';
  EXCEPTION WHEN check_violation THEN NULL;
  END;

  -- #6 CPF valido aceito
  BEGIN
    INSERT INTO public.alunos (nome, cpf) VALUES ('CPF Valido', '111.444.777-35');
  EXCEPTION WHEN OTHERS THEN
    RAISE EXCEPTION 'FALHOU: CPF valido recusado: %', SQLERRM;
  END;

  -- #6 responsavel_cpf pode repetir (mesmo responsavel, varios filhos)
  BEGIN
    INSERT INTO public.alunos (nome, responsavel_cpf)
    VALUES ('Filho 1', '111.444.777-35'), ('Filho 2', '111.444.777-35');
  EXCEPTION WHEN OTHERS THEN
    RAISE EXCEPTION 'FALHOU: responsavel_cpf repetido foi bloqueado: %', SQLERRM;
  END;

  RAISE NOTICE 'Regras #5 e #6: ok';
END $$;
