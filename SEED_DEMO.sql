-- ============================================================
-- SEED DE DEMONSTRAÇÃO - 5 professores, 8 turmas, 20 alunos
-- ============================================================
-- Para conferir a interface (painel, turmas, matrículas, financeiro,
-- relatórios) com dados realistas: alunos de todas as idades, turmas
-- ativas e uma encerrada, matrículas mensais / carnê (6x e 12x) /
-- aula avulsa / individual (VIP), lançamentos pagos, atrasados e
-- pendentes, ajustes (descontos), aulas ministradas e desempenhos.
--
-- Executar no Supabase > SQL Editor (idempotente: roda de novo sem
-- duplicar nada). Tudo em uma transação: ou entra tudo, ou nada.
--
-- Limpeza: apagar o bloco "DELETE DE LIMPEZA" no fim do arquivo.
-- ============================================================

-- Auxiliar: gera CPF válido (dígitos verificadores) a partir de 9 dígitos.
-- Mesma técnica do SEED_TESTE.sql; removida no final.
CREATE OR REPLACE FUNCTION public.seed_cpf(base9 TEXT) RETURNS TEXT
LANGUAGE plpgsql IMMUTABLE AS $$
DECLARE
  d    TEXT := lpad(base9, 9, '0');
  soma INT;
  dv   INT;
BEGIN
  soma := 0;
  FOR i IN 1..9 LOOP
    soma := soma + substr(d, i, 1)::INT * (11 - i);
  END LOOP;
  dv := (soma * 10) % 11;
  IF dv = 10 THEN dv := 0; END IF;
  d := d || dv::TEXT;

  soma := 0;
  FOR i IN 1..10 LOOP
    soma := soma + substr(d, i, 1)::INT * (12 - i);
  END LOOP;
  dv := (soma * 10) % 11;
  IF dv = 10 THEN dv := 0; END IF;
  d := d || dv::TEXT;

  RETURN regexp_replace(d, '(\d{3})(\d{3})(\d{3})(\d{2})', '\1.\2.\3-\4');
END;
$$;

DO $$
DECLARE
  -- ---------- listas ----------
  prof_n    TEXT[] := ARRAY['Marina Duarte','Rafael Negreiros','Camila Sato','Bruno Tavares','Helena Prado'];
  prof_i    TEXT[] := ARRAY['Piano','Violão','Canto','Bateria','Violino'];
  prof_f    TEXT[] := ARRAY['Bacharel em Música (UFSP)','Licenciatura em Música (UNICAMP)',
                           'Bacharel em Canto Popular (UFMG)','Técnico em Música (Conservatório)',
                           'Bacharel em Música (UFRJ)'];
  prof_a    BOOLEAN[] := ARRAY[true, true, true, true, false];  -- Helena inativa (demonstra a RN14)

  turma_n  TEXT[] := ARRAY['Piano Iniciante A','Piano Intermediário B','Violão Grupo Kids',
                           'Guitarra Elétrica','Canto Popular','Bateria Iniciante',
                           'Teclado Teens','Violino Crianças'];
  turma_i  TEXT[] := ARRAY['Piano','Piano','Violão','Guitarra','Canto','Bateria','Teclado','Violino'];
  turma_p  INT[]  := ARRAY[1, 1, 2, 2, 3, 4, 5, 1];
  turma_d  TEXT[] := ARRAY['segunda','quarta','sexta','terça','quinta','sábado','segunda','quarta'];
  turma_h  TEXT[] := ARRAY['17:00','18:30','16:00','19:00','18:00','10:00','19:30','17:00'];
  turma_v  NUMERIC(10,2)[] := ARRAY[180,210,150,195,165,180,170,190];
  turma_s  TEXT[] := ARRAY['ativa','ativa','ativa','ativa','ativa','ativa','encerrada','ativa'];

  aluno_n  TEXT[] := ARRAY['Ana Clara Santos','Bruno Henrique Costa','Camila Ferreira','Daniel Oliveira',
                           'Eduarda Martins','Felipe Rodrigues','Gabriela Alves','Heitor Pereira',
                           'Isabela Cardoso','João Pedro Nunes','Larissa Mendes','Leonardo Barbosa',
                           'Letícia Rocha','Lucas Gonçalves','Manuela Dias','Matheus Carvalho',
                           'Nicole Fernandes','Otávio Ramos','Paula Teixeira','Pedro Henrique Sousa'];
  menores  INT[]  := ARRAY[1,4,6,9,12,17];
  resp_n   TEXT[] := ARRAY['Maria Santos','Paulo Cardoso','Jorge Mendes','André Machado',
                           'Cláudia Ribeiro','Sandra Dias'];
  bairro   TEXT[] := ARRAY['Pinheiros','Moema','Vila Mariana','Santana','Tatuapé','Perdizes'];

  -- ---------- variáveis ----------
  pid BIGINT; prof_ids BIGINT[];
  tid BIGINT; turma_ids BIGINT[];
  aid BIGINT; aluno_ids BIGINT[];
  mid BIGINT; mat_ids BIGINT[];
  gid BIGINT; grade_ids BIGINT[];
  cmid BIGINT;
  i INT; p INT; k INT;
  dt DATE; comp DATE; ven DATE; parc NUMERIC(10,2); baseN NUMERIC(10,2);
  qtd INT; vdia INT; vdia_al INT; rg_x TEXT; curso TEXT; mtc BIGINT;
  st TEXT; stl TEXT; descr TEXT; i_aluno INT; i_turma INT; ev NUMERIC(5,2); av TEXT;
BEGIN
  -- ---------- guarda de idempotência ----------
  IF EXISTS (SELECT 1 FROM public.professores WHERE nome = 'Marina Duarte') THEN
    RAISE NOTICE 'Seed demo já aplicado — nada a fazer.';
    RETURN;
  END IF;

  -- ============================================================
  -- 1) 5 PROFESSORES
  -- ============================================================
  FOR i IN 1..5 LOOP
    INSERT INTO public.professores
      (nome, cpf, nascimento, instrumento, email, telefone, formacao, endereco, bairro, cidade, cep, ativo)
    VALUES (
      prof_n[i],
      public.seed_cpf((100000000 + i * 48211)::text),
      to_date('1982-01-01','YYYY-MM-DD') + (i * 97),
      prof_i[i],
      lower(replace(prof_n[i], ' ', '.')) || '@escola.demo',
      '(11) 9' || lpad((8100 + i * 211)::text, 8, '0'),
      prof_f[i],
      'Rua das Artes, ' || (120 + i * 15),
      bairro[(i % 6) + 1],
      'São Paulo - SP',
      '054' || lpad((100 + i * 13)::text, 4, '0'),
      prof_a[i]
    ) RETURNING id INTO pid;
    prof_ids[i] := pid;
  END LOOP;

  -- ============================================================
  -- 2) 8 TURMAS (7 ativas + 1 encerrada; a encerrada fica com a
  --    professora inativa para aparecer o aviso da RN14)
  -- ============================================================
  FOR i IN 1..8 LOOP
    INSERT INTO public.turmas (nome, instrumento, professor_id, dia_semana, horario, valor_mensal, status)
    VALUES (turma_n[i], turma_i[i], prof_ids[turma_p[i]], turma_d[i], turma_h[i]::time, turma_v[i], turma_s[i]::text::status_turma)
    RETURNING id INTO tid;
    turma_ids[i] := tid;
  END LOOP;

  -- ============================================================
  -- 3) 20 ALUNOS (6 menores com responsável, 2 sem CPF)
  -- ============================================================
  FOR i IN 1..20 LOOP
    i_aluno := array_position(menores, i);
    INSERT INTO public.alunos
      (nome, cpf, nascimento, telefone, email, endereco, bairro, cidade, cep, observacao, ativo,
       responsavel_nome, responsavel_cpf, responsavel_telefone, parentesco)
    VALUES (
      aluno_n[i],
      (CASE WHEN i IN (7, 14) THEN NULL
            ELSE public.seed_cpf((200000000 + i * 61631)::text) END),
      (CASE WHEN i_aluno IS NOT NULL THEN to_date('2013-01-01','YYYY-MM-DD') + (i * 71)
            ELSE to_date('1990-01-01','YYYY-MM-DD') + (i * 213) END),
      '(11) 9' || lpad((6200 + i * 173)::text, 8, '0'),
      lower(replace(aluno_n[i], ' ', '.')) || '@aluno.demo',
      'Rua ' || (CASE WHEN i % 2 = 0 THEN 'das Violetas' ELSE 'dos Ipês' END) || ', ' || (80 + i * 23),
      bairro[(i % 6) + 1],
      'São Paulo - SP',
      '05' || lpad((400 + i * 11)::text, 4, '0'),
      'Aluno de demonstração',
      true,
      (CASE WHEN i_aluno IS NOT NULL THEN resp_n[i_aluno] ELSE NULL END),
      (CASE WHEN i_aluno IS NOT NULL THEN public.seed_cpf((300000000 + i * 3091)::text) ELSE NULL END),
      (CASE WHEN i_aluno IS NOT NULL THEN '(11) 9' || lpad((7500 + i * 91)::text, 8, '0') ELSE NULL END),
      (CASE WHEN i_aluno IS NOT NULL THEN (CASE WHEN i % 2 = 0 THEN 'mae' ELSE 'pai' END) ELSE NULL END)
    ) RETURNING id INTO aid;
    aluno_ids[i] := aid;
  END LOOP;

  -- ============================================================
  -- 4) 18 MATRÍCULAS
  --    1-12  turma mensal      | 13-15 turma parcelado (carnê)
  --    16-17 individual mensal (VIP) | 18 individual avulsa
  --    19-20 turma mensal trancada / concluída
  -- ============================================================
  FOR i IN 1..20 LOOP
    IF i <= 12 THEN
      i_turma := ((i - 1) % 8) + 1;
      vdia := (CASE WHEN i % 3 = 0 THEN 15 WHEN i % 3 = 1 THEN 10 ELSE 5 END);
      dt := (date_trunc('month', CURRENT_DATE) - interval '3 months')::date + (i % 20);
      INSERT INTO public.matriculas
        (aluno_id, turma_id, tipo, professor_id, tipo_pagamento, valor_matricula, matricula_forma_pagamento,
         valor_mensal, valor_aula, status, data_inicio, dia_vencimento, observacao)
      VALUES (aluno_ids[i], turma_ids[i_turma], 'turma', NULL, 'mensal', 60, 'pix',
              turma_v[i_turma], 0, 'ativa', dt, vdia, 'Mensalidade recorrente (demo)')
      RETURNING id INTO mid;
    ELSIF i <= 15 THEN
      i_turma := CASE WHEN i = 13 THEN 2 WHEN i = 14 THEN 3 WHEN i = 15 THEN 8 END;
      qtd := CASE WHEN i = 14 THEN 12 ELSE 6 END;
      vdia := CASE WHEN i = 13 THEN 5 WHEN i = 14 THEN 15 ELSE 10 END;
      dt := (date_trunc('month', CURRENT_DATE) - interval '2 months')::date;
      INSERT INTO public.matriculas
        (aluno_id, turma_id, tipo, professor_id, tipo_pagamento, valor_matricula, matricula_forma_pagamento,
         valor_total, parcelas, valor_mensal, valor_aula, status, data_inicio, dia_vencimento, observacao)
      VALUES (aluno_ids[i], turma_ids[i_turma], 'turma', NULL, 'parcelado', 90, 'dinheiro',
              turma_v[i_turma] * qtd, qtd, 0, 0, 'ativa', dt, vdia, 'Carnê ' || qtd || 'x (demo)')
      RETURNING id INTO mid;
    ELSIF i <= 17 THEN
      -- Aluno VIP: aula individual com professor fixo
      i_turma := CASE WHEN i = 16 THEN 2 ELSE 3 END;   -- 2 = Rafael, 3 = Camila
      vdia := CASE WHEN i = 16 THEN 10 ELSE 15 END;
      dt := (date_trunc('month', CURRENT_DATE) - interval '3 months')::date + 5;
      INSERT INTO public.matriculas
        (aluno_id, turma_id, tipo, professor_id, tipo_pagamento, valor_matricula, matricula_forma_pagamento,
         valor_mensal, valor_aula, status, data_inicio, dia_vencimento, dia_semana, horario, observacao)
      VALUES (aluno_ids[i], NULL, 'individual', prof_ids[i_turma], 'mensal', 50, 'cartao',
              CASE WHEN i = 16 THEN 280 ELSE 260 END, 0, 'ativa', dt, vdia,
              (CASE WHEN i = 16 THEN 'quinta' ELSE 'sexta' END), (CASE WHEN i = 16 THEN '08:00' ELSE '09:30' END)::time,
              'Aluno VIP - aula individual mensal (demo)')
      RETURNING id INTO mid;
    ELSIF i = 18 THEN
      dt := (date_trunc('month', CURRENT_DATE) - interval '2 months')::date + 3;
      INSERT INTO public.matriculas
        (aluno_id, turma_id, tipo, professor_id, tipo_pagamento, valor_matricula, matricula_forma_pagamento,
         valor_mensal, valor_aula, status, data_inicio, dia_vencimento, dia_semana, horario, observacao)
      VALUES (aluno_ids[18], NULL, 'individual', prof_ids[4], 'avulsa', 0, 'pix',
              0, 95, 'ativa', dt, 5, 'quarta', '11:00', 'Aula avulsa (demo)')
      RETURNING id INTO mid;
    ELSE
      i_turma := CASE WHEN i = 19 THEN 4 ELSE 6 END;
      dt := (date_trunc('month', CURRENT_DATE) - interval '4 months')::date;
      INSERT INTO public.matriculas
        (aluno_id, turma_id, tipo, professor_id, tipo_pagamento, valor_matricula, matricula_forma_pagamento,
         valor_mensal, valor_aula, status, data_inicio, dia_vencimento, observacao)
      VALUES (aluno_ids[i], turma_ids[i_turma], 'turma', NULL, 'mensal', 0, 'pix',
              turma_v[i_turma], 0,
              (CASE WHEN i = 19 THEN 'trancada' ELSE 'concluida' END)::status_matricula,
              dt, 5,
              (CASE WHEN i = 19 THEN 'Turma trancada (aluno mudou de cidade)' ELSE 'Curso concluído (demo)' END))
      RETURNING id INTO mid;
    END IF;
    mat_ids[i] := mid;
  END LOOP;

  -- ============================================================
  -- 5) GRADE DE CONTEÚDOS (8 itens) — base do progresso das turmas
  -- ============================================================
  FOR i IN 1..8 LOOP
    INSERT INTO public.grade_conteudos (titulo, descricao, modulo, nivel, ordem, tempo_estimado, ativo)
    VALUES (
      (ARRAY['Escalas e arpejos','Leitura de partituras','Postura e técnica do instrumento',
             'Ritmo básico e percussão corporal','Acordes básicos e cifragem',
             'Improvisação melódica','Uso do metrônomo e andamento','Apresentação de repertório'])[i],
      'Conteúdo ' || i || ' do percurso de formação.',
      (CASE WHEN i <= 4 THEN 'Módulo 1 - Fundamentos' WHEN i <= 7 THEN 'Módulo 2 - Harmonia' ELSE 'Módulo 3 - Performance' END),
      (CASE WHEN i <= 4 THEN 'Iniciante' WHEN i <= 7 THEN 'Intermediário' ELSE 'Avançado' END),
      i,
      (CASE WHEN i = 8 THEN interval '120 minutes' ELSE interval '45 minutes' END),
      true
    ) RETURNING id INTO gid;
    grade_ids[i] := gid;
  END LOOP;

  -- ============================================================
  -- 6) AULAS MINISTRADAS (3 por turma ativa, 1 na encerrada)
  -- ============================================================
  FOR i_turma IN 1..8 LOOP
    FOR k IN 1..(CASE WHEN turma_s[i_turma] = 'encerrada' THEN 1 ELSE 3 END) LOOP
      SELECT professor_id INTO pid FROM public.turmas WHERE id = turma_ids[i_turma];
      ev := (CASE WHEN k = 1 THEN 30 WHEN k = 2 THEN 55 ELSE 78 END);
      INSERT INTO public.conteudos_ministrados
        (turma_id, matricula_id, professor_id, grade_id, data_aula, titulo, descricao, evolucao_turma, observacoes)
      VALUES (
        turma_ids[i_turma], NULL, pid, grade_ids[k],
        (CURRENT_DATE - ((4 - k) * 7))::date,
        (SELECT titulo FROM public.grade_conteudos WHERE id = grade_ids[k]),
        'Aula ' || k || ' do módulo.',
        ev,
        'Aula registrada pela demonstração'
      ) RETURNING id INTO cmid;
    END LOOP;
  END LOOP;

  -- ============================================================
  -- 7) DESEMPENHOS (um por aluno x aula da turma)
  -- ============================================================
  FOR i IN 1..20 LOOP
    FOR cmid IN
      SELECT cm.id FROM public.conteudos_ministrados cm
      WHERE (cm.turma_id IS NOT NULL
             AND cm.turma_id = (SELECT turma_id FROM public.matriculas WHERE id = mat_ids[i]))
         OR cm.matricula_id = mat_ids[i]
    LOOP
      av := (ARRAY['Ótimo','Bom','Muito bom','Em evolução','Satisfatório'])[1 + ((cmid + i) % 5)];
      INSERT INTO public.desempenhos (aluno_id, conteudo_id, desempenho, avaliacao, data)
      SELECT aluno_ids[i], cmid, 60 + ((cmid * 7 + i * 3) % 36), av,
             (SELECT data_aula FROM public.conteudos_ministrados WHERE id = cmid)
      ON CONFLICT (aluno_id, conteudo_id) DO NOTHING;
    END LOOP;
  END LOOP;

  -- ============================================================
  -- 8) FINANCEIRO
  --    8.1 Taxa de matrícula — criada automaticamente pelo trigger
  --        (trig_financeiro_matricula) para as matrículas com valor_matricula > 0
  --    8.2 Mensalidades das matrículas mensais (4 competências)
  --    8.3 Parcelas do carnê (6x e 12x)
  --    8.4 Ajustes (desconto negativo e Material positivo)
  --    8.5 Aulas avulsas (o trigger cria a cobrança; abaixo marcamos uma como paga)
  -- ============================================================

  -- 8.2 Mensalidades
  FOR i IN 1..20 LOOP
    IF i IN (13,14,15,18) THEN
      CONTINUE;                                  -- carnê e avulsa: tratados abaixo
    END IF;
    SELECT tipo_pagamento, data_inicio, dia_vencimento, turma_id, status
      INTO rg_x, dt, vdia_al, tid, st FROM public.matriculas WHERE id = mat_ids[i];
    IF rg_x <> 'mensal' THEN CONTINUE; END IF;

    SELECT COALESCE(t.nome, 'Aluno VIP') INTO curso FROM public.turmas t WHERE t.id = tid;
    IF curso IS NULL THEN curso := 'Aluno VIP'; END IF;

    FOR p IN 0..3 LOOP
      comp := (date_trunc('month', dt)::date + make_interval(months => p))::date;
      EXIT WHEN comp > date_trunc('month', CURRENT_DATE)::date;
      ven := comp + (vdia_al - 1) * interval '1 day';
      stl := CASE
              WHEN ven >= CURRENT_DATE THEN 'pendente'
              WHEN (i + p) % 5 = 0      THEN 'atrasada'
              ELSE 'paga'
            END;
      INSERT INTO public.financeiro
        (aluno_id, matricula_id, tipo, descricao, valor, vencimento, competencia, status, data_pagamento, forma_pagamento)
      VALUES (
        aluno_ids[i], mat_ids[i], 'mensalidade',
        'Mensalidade - ' || curso,
        (SELECT valor_mensal FROM public.matriculas WHERE id = mat_ids[i]),
        ven, comp, stl::status_lancamento,
        (CASE WHEN stl = 'paga' THEN ven ELSE NULL END),
        (CASE WHEN stl = 'paga' THEN 'pix'::forma_pagamento ELSE NULL END)
      )
      ON CONFLICT (matricula_id, competencia, tipo) WHERE tipo = 'mensalidade' DO NOTHING;
    END LOOP;
  END LOOP;

  -- 8.3 Parcelas do carnê (mesma estrutura da RPC gerar_carne)
  FOR i IN 13..15 LOOP
    SELECT tipo_pagamento, parcelas, valor_total, data_inicio, dia_vencimento, turma_id
      INTO rg_x, qtd, baseN, dt, vdia_al, tid FROM public.matriculas WHERE id = mat_ids[i];
    SELECT COALESCE(nome, 'Aluno VIP') INTO curso FROM public.turmas t WHERE t.id = tid;
    IF curso IS NULL THEN curso := 'Aluno VIP'; END IF;
    FOR p IN 0..qtd - 1 LOOP
      comp := (date_trunc('month', dt)::date + make_interval(months => p))::date;
      EXIT WHEN comp > date_trunc('month', CURRENT_DATE)::date;
      ven := comp + (vdia_al - 1) * interval '1 day';
      parc := CASE WHEN p = qtd - 1 THEN baseN - (qtd - 1) * round(baseN / qtd, 2) ELSE round(baseN / qtd, 2) END;
      stl := CASE WHEN ven >= CURRENT_DATE THEN 'pendente' ELSE 'paga' END;
      INSERT INTO public.financeiro
        (aluno_id, matricula_id, tipo, descricao, valor, vencimento, competencia, status, data_pagamento, forma_pagamento)
      VALUES (
        aluno_ids[i], mat_ids[i], 'mensalidade',
        'Parcela ' || (p + 1) || '/' || qtd || ' - ' || curso,
        parc, ven, comp, stl::status_lancamento,
        (CASE WHEN stl = 'paga' THEN ven ELSE NULL END),
        (CASE WHEN stl = 'paga' THEN 'boleto'::forma_pagamento ELSE NULL END)
      )
      ON CONFLICT (matricula_id, competencia, tipo) WHERE tipo = 'mensalidade' DO NOTHING;
    END LOOP;
  END LOOP;

  -- 8.4 Ajustes: desconto (negativo), material (positivo)
  INSERT INTO public.financeiro
    (aluno_id, matricula_id, tipo, descricao, valor, vencimento, competencia, status, data_pagamento, forma_pagamento)
  VALUES
    (aluno_ids[3],  mat_ids[3],  'ajuste', 'Desconto - família com 2 irmãos (demo)', -50.00,
     date_trunc('month', CURRENT_DATE)::date, date_trunc('month', CURRENT_DATE)::date, 'paga',
     CURRENT_DATE, 'pix'),
    (aluno_ids[8],  mat_ids[8],  'ajuste', 'Desconto - pagamento antecipado (demo)', -30.00,
     date_trunc('month', CURRENT_DATE)::date, date_trunc('month', CURRENT_DATE)::date, 'paga',
     CURRENT_DATE, 'pix'),
    (aluno_ids[12], mat_ids[12], 'ajuste', 'Material - apostila e pasta (demo)', 25.00,
     date_trunc('month', CURRENT_DATE)::date, date_trunc('month', CURRENT_DATE)::date, 'pendente',
     NULL, NULL);

  -- 8.5 Aulas avulsas: o trigger cria a cobrança; uma delas é marcada como paga
  FOR k IN 1..3 LOOP
    INSERT INTO public.conteudos_ministrados
      (turma_id, matricula_id, professor_id, grade_id, data_aula, titulo, descricao, evolucao_turma, observacoes)
    VALUES (
      NULL, mat_ids[18], prof_ids[4], grade_ids[k],
      (CURRENT_DATE - ((4 - k) * 10))::date,
      'Aula particular ' || k,
      'Aula avulsa registrada pela demonstração',
      NULL, 'Aula avulsa (demo)'
    );
  END LOOP;

  UPDATE public.financeiro
     SET status = 'paga'::status_lancamento, data_pagamento = CURRENT_DATE - 10, forma_pagamento = 'dinheiro'
   WHERE tipo = 'aula_avulsa'
     AND descricao = 'Aula avulsa - Aula particular 1';

  -- 8.6 Aulas individuais dos Alunos VIP (para o progresso individual não ficar vazio)
  FOR i IN 16..17 LOOP
    FOR k IN 1..2 LOOP
      INSERT INTO public.conteudos_ministrados
        (turma_id, matricula_id, professor_id, grade_id, data_aula, titulo, descricao, evolucao_turma, observacoes)
      VALUES (
        NULL, mat_ids[i], prof_ids[(CASE WHEN i = 16 THEN 2 ELSE 3 END)], grade_ids[k],
        (CURRENT_DATE - ((3 - k) * 14))::date,
        'Aula individual ' || k,
        'Aula particular com professor fixo (demo)',
        NULL, 'Aluno VIP (demo)'
      );
    END LOOP;
  END LOOP;

  -- ============================================================
  -- 9) RESUMO
  -- ============================================================
  RAISE NOTICE 'Seed demo aplicado: 5 professores, 8 turmas, 20 alunos, 20 matrículas, % lançamentos financeiros.',
    (SELECT count(*) FROM public.financeiro);
END $$;

-- A função auxiliar do seed não é usada em produção.
DROP FUNCTION IF EXISTS public.seed_cpf(TEXT);


-- ============================================================
-- DELETE DE LIMPEZA (rode só se quiser remover a demonstração)
-- ============================================================
-- DELETE FROM public.desempenhos WHERE conteudo_id IN (SELECT id FROM public.conteudos_ministrados);
-- DELETE FROM public.conteudos_ministrados;
-- DELETE FROM public.financeiro;
-- DELETE FROM public.matriculas;
-- DELETE FROM public.alunos WHERE observacao = 'Aluno de demonstração';
-- DELETE FROM public.turmas WHERE nome IN ('Piano Iniciante A','Piano Intermediário B','Violão Grupo Kids',
--   'Guitarra Elétrica','Canto Popular','Bateria Iniciante','Teclado Teens','Violino Crianças');
-- DELETE FROM public.professores WHERE email LIKE '%@escola.demo';
-- DELETE FROM public.grade_conteudos WHERE modulo IN ('Módulo 1 - Fundamentos','Módulo 2 - Harmonia','Módulo 3 - Performance');
