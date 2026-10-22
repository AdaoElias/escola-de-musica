-- Item #10 / RN14: professor so pode ser inativado se nao tiver turma ativa;
-- turma ativa exige professor ativo.
DO $$
DECLARE
  prof_id  BIGINT;
  turma_id BIGINT;
  aluno_id BIGINT;
  n        INTEGER;
BEGIN
  INSERT INTO public.professores (nome, instrumento) VALUES ('Professor RN14', 'Teclado')
    ON CONFLICT DO NOTHING;
  SELECT id INTO prof_id FROM public.professores WHERE nome = 'Professor RN14';
  IF prof_id IS NULL THEN RAISE EXCEPTION 'FALHOU: professor de teste nao criado'; END IF;

  INSERT INTO public.alunos (nome) VALUES ('Aluno RN14') ON CONFLICT DO NOTHING;
  SELECT id INTO aluno_id FROM public.alunos WHERE nome = 'Aluno RN14';

  INSERT INTO public.turmas (nome, instrumento, professor_id, valor_mensal, status)
  SELECT 'Turma RN14', 'Teclado', prof_id, 150.00, 'ativa'
  WHERE NOT EXISTS (SELECT 1 FROM public.turmas WHERE nome = 'Turma RN14');
  SELECT id INTO turma_id FROM public.turmas WHERE nome = 'Turma RN14';

  -- Inativar professor com turma ativa deve falhar
  BEGIN
    UPDATE public.professores SET ativo = false WHERE id = prof_id;
    RAISE EXCEPTION 'FALHOU: professor com turma ativa foi inativado';
  EXCEPTION WHEN OTHERS THEN
    IF SQLERRM NOT LIKE '%turma(s) ativa(s)%' THEN
      RAISE EXCEPTION 'FALHOU: erro inesperado ao inativar: %', SQLERRM;
    END IF;
  END;

  -- Ativar uma turma com professor inativo deve falhar
  BEGIN
    UPDATE public.professores SET ativo = false WHERE id = prof_id;
    RAISE EXCEPTION 'FALHOU: inativacao deveria ter falhado';
  EXCEPTION WHEN OTHERS THEN
    IF SQLERRM NOT LIKE '%turma(s) ativa(s)%' THEN
      RAISE EXCEPTION 'FALHOU: erro inesperado: %', SQLERRM;
    END IF;
  END;

  -- Encerrando a turma, a inativacao passa
  UPDATE public.turmas SET status = 'encerrada' WHERE id = turma_id;
  UPDATE public.professores SET ativo = false WHERE id = prof_id;

  SELECT count(*) INTO n FROM public.professores WHERE id = prof_id AND ativo = false;
  IF n <> 1 THEN RAISE EXCEPTION 'FALHOU: professor nao foi inativado apos encerrar a turma'; END IF;

  -- Reativar a turma com professor inativo deve falhar
  BEGIN
    UPDATE public.turmas SET status = 'ativa' WHERE id = turma_id;
    RAISE EXCEPTION 'FALHOU: turma ativa com professor inativo foi aceita';
  EXCEPTION WHEN OTHERS THEN
    IF SQLERRM NOT LIKE '%Turma ativa exige professor ativo%' THEN
      RAISE EXCEPTION 'FALHOU: erro inesperado: %', SQLERRM;
    END IF;
  END;

  -- Transferir a turma para um professor ativo deve funcionar
  INSERT INTO public.professores (nome, instrumento) VALUES ('Professor Ativo RN14', 'Viola')
    ON CONFLICT DO NOTHING;
  UPDATE public.turmas t
     SET professor_id = (SELECT id FROM public.professores WHERE nome = 'Professor Ativo RN14'),
         status = 'ativa'
   WHERE t.id = turma_id;

  SELECT count(*) INTO n FROM public.turmas WHERE id = turma_id AND status = 'ativa';
  IF n <> 1 THEN RAISE EXCEPTION 'FALHOU: transferencia de turma falhou'; END IF;

  RAISE NOTICE 'RN14 (professor ativo): ok';
END $$;
