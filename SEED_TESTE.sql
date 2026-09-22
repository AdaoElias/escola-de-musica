-- ============================================================
-- SEED DE TESTE - 10 professores, 30 alunos, 30 matriculas
-- Instrumentos diversos (+ turmas e parcelas de carne)
-- Executar no Supabase > SQL Editor (idempotente: roda de novo sem duplicar)
-- ============================================================

-- Turma agora pode ser parcelada (carnê 1/6/12x), não só mensal
ALTER TABLE public.matriculas DROP CONSTRAINT IF EXISTS matriculas_check2;
ALTER TABLE public.matriculas ADD CONSTRAINT matriculas_check2
  CHECK (tipo <> 'turma' OR tipo_pagamento::text IN ('mensal', 'parcelado'));

DO $$
DECLARE
  instr TEXT[] := ARRAY['Violão','Guitarra','Teclado','Bateria','Canto','Violino','Flauta Transversal','Saxofone','Percussão','Baixo'];
  profs TEXT[] := ARRAY['Ana Beatriz Souza','Carlos Eduardo Lima','Fernanda Rocha','Gustavo Almeida','Juliana Castro','Marcos Paulo Silva','Patrícia Nunes','Rafael Martins','Renata Oliveira','Thiago Ferreira'];
  formas TEXT[] := ARRAY['Bacharel em Música','Licenciatura em Música','Técnico em Música','Bacharel em Música'] ;
  bairros TEXT[] := ARRAY['Centro','Vila Mariana','Tatuapé','Moema','Pinheiros','Santana'];
  dias TEXT[] := ARRAY['segunda','terca','quarta','quinta','sexta','sabado'];
  alunos_n TEXT[] := ARRAY['Ana Clara Santos','Bruno Henrique Costa','Camila Ferreira','Daniel Oliveira','Eduarda Martins','Felipe Rodrigues','Gabriela Alves','Heitor Pereira','Isabela Cardoso','João Pedro Nunes','Larissa Mendes','Leonardo Barbosa','Letícia Rocha','Lucas Gonçalves','Manuela Dias','Matheus Carvalho','Nicole Fernandes','Otávio Ramos','Paula Teixeira','Pedro Henrique Sousa','Rafaela Pinto','Raquel Freitas','Rodrigo Lopes','Sabrina Machado','Samuel Nogueira','Sônia Bezerra','Tainá Ribeiro','Thiago Moraes','Vitória Araújo','Yago Lima'];
  menores INT[] := ARRAY[1, 9, 11, 24, 27];
  resp_n TEXT[] := ARRAY['Maria Santos','Paulo Cardoso','Jorge Mendes','André Machado','Cláudia Ribeiro'];
  pid BIGINT; prof_ids BIGINT[];
  tid BIGINT; turma_ids BIGINT[];
  aid BIGINT; aluno_ids BIGINT[];
  mid BIGINT;
  i INT; p INT;
  dt DATE; comp DATE; ven DATE;
  baseN NUMERIC(10,2); parc NUMERIC(10,2);
  curso TEXT; qtd INT; mtc BIGINT;
  rg_x TEXT; vdia INT;
BEGIN

  -- ---------- 10 professores ----------
  FOR i IN 1..10 LOOP
    SELECT id INTO pid FROM public.professores WHERE nome = profs[i];
    IF pid IS NULL THEN
      INSERT INTO public.professores (nome, cpf, nascimento, instrumento, email, telefone, formacao, endereco, bairro, cidade, cep, ativo)
      VALUES (
        profs[i],
        regexp_replace(lpad((i * 7919)::text, 11, '0'), '([0-9]{3})([0-9]{3})([0-9]{3})([0-9]{2})', '\1.\2.\3-\4'),
        to_date('1985-01-01','YYYY-MM-DD') + (i * 41),
        instr[i],
        'prof' || i || '@escola.com',
        '(11) 9' || lpad((9000 + i * 137)::text, 8, '0'),
        formas[(i % 4) + 1],
        'Rua das Artes, ' || (i * 37),
        bairros[(i % 6) + 1],
        'São Paulo - SP',
        '01' || lpad((i * 27)::text, 6, '0'),
        true
      ) RETURNING id INTO pid;
    END IF;
    prof_ids[i] := pid;
  END LOOP;

  -- ---------- 10 turmas (instrumentos diversos) ----------
  FOR i IN 1..10 LOOP
    SELECT id INTO tid FROM public.turmas WHERE nome = 'Turma de ' || instr[i];
    IF tid IS NULL THEN
      INSERT INTO public.turmas (nome, instrumento, professor_id, dia_semana, horario, valor_mensal, status)
      VALUES ('Turma de ' || instr[i], instr[i], prof_ids[i],
              dias[(i % 6) + 1],
              (CASE WHEN i % 3 = 0 THEN '17:00' WHEN i % 3 = 1 THEN '18:00' ELSE '19:00' END)::time,
              150 + (i * 15),
              'ativa'
      ) RETURNING id INTO tid;
    END IF;
    turma_ids[i] := tid;
  END LOOP;

  -- ---------- 30 alunos (5 menores com responsavel) ----------
  FOR i IN 1..30 LOOP
    SELECT id INTO aid FROM public.alunos WHERE nome = alunos_n[i];
    IF aid IS NULL THEN
      rg_x := lpad((i * 6163)::text, 11, '0');
      INSERT INTO public.alunos (nome, cpf, nascimento, telefone, email, endereco, bairro, cidade, cep, observacao, ativo,
                                 responsavel_nome, responsavel_cpf, responsavel_telefone, parentesco)
      VALUES (
        alunos_n[i],
        regexp_replace(rg_x, '([0-9]{3})([0-9]{3})([0-9]{3})([0-9]{2})', '\1.\2.\3-\4'),
        (CASE WHEN i = ANY(menores) THEN to_date('2010-01-01','YYYY-MM-DD') + (i * 140) ELSE to_date('1998-01-01','YYYY-MM-DD') + (i * 210) END),
        '(11) 9' || lpad((9000 + i * 173)::text, 8, '0'),
        'aluno' || i || '@escola.com',
        'Rua das Notas, ' || (i * 12),
        bairros[(i % 6) + 1],
        'São Paulo - SP',
        '01' || lpad((i * 33)::text, 6, '0'),
        'Aluno de teste (seed)',
        true,
        (CASE WHEN i = ANY(menores) THEN
          resp_n[array_position(menores, i)]::text
        ELSE NULL END),
        (CASE WHEN i = ANY(menores) THEN
          regexp_replace(lpad((i * 4444)::text, 11, '0'), '([0-9]{3})([0-9]{3})([0-9]{3})([0-9]{2})', '\1.\2.\3-\4')
        ELSE NULL END),
        (CASE WHEN i = ANY(menores) THEN '(11) 9' || lpad((8000 + i * 61)::text, 8, '0') ELSE NULL END),
        (CASE WHEN i = ANY(menores) THEN (CASE WHEN i % 2 = 0 THEN 'mae' ELSE 'pai' END) ELSE NULL END)
      ) RETURNING id INTO aid;
    END IF;
    aluno_ids[i] := aid;
  END LOOP;

  -- ---------- 30 matriculas ----------
  -- i 1..10 -> turma parcelado | 11..15 -> turma mensal | 16..23 -> individual parcelado (VIP)
  -- 24..26 -> individual mensal | 27..30 -> individual avulsa
  FOR i IN 1..30 LOOP
    IF i <= 15 THEN
      tid := turma_ids[(i % 10) + 1];
      SELECT id INTO mid FROM public.matriculas
        WHERE aluno_id = aluno_ids[i] AND tipo = 'turma' AND turma_id = tid;
    ELSE
      pid := prof_ids[(i % 10) + 1];
      SELECT id INTO mid FROM public.matriculas
        WHERE aluno_id = aluno_ids[i] AND tipo = 'individual' AND professor_id = pid;
    END IF;

    IF mid IS NULL THEN
      dt := to_date('2026-01-01','YYYY-MM-DD') + ((i - 1) * 11);
      IF i BETWEEN 1 AND 10 THEN
        -- turma parcelado (qtd variavel)
        qtd := (CASE WHEN i % 3 = 0 THEN 12 WHEN i % 2 = 0 THEN 6 ELSE 1 END);
        INSERT INTO public.matriculas
          (aluno_id, turma_id, tipo, professor_id, tipo_pagamento,
           valor_matricula, matricula_forma_pagamento, valor_total, parcelas, dia_vencimento,
           valor_mensal, valor_aula, status, data_inicio,
           dia_semana, horario, observacao)
        SELECT aluno_ids[i], tid, 'turma', NULL, 'parcelado',
               (CASE WHEN i % 4 = 0 THEN 0 ELSE 90 END), (CASE WHEN i % 4 = 1 THEN 'pix' WHEN i % 4 = 2 THEN 'dinheiro' WHEN i % 4 = 3 THEN 'cartao' ELSE 'pix' END)::forma_pagamento,
               (SELECT valor_mensal FROM public.turmas WHERE id = tid)::numeric(10,2) * qtd,
               qtd, (CASE WHEN i % 3 = 0 THEN 15 WHEN i % 2 = 0 THEN 10 ELSE 5 END),
               0, 0, 'ativa', dt, NULL, NULL, 'Carnê ' || qtd || 'x (seed)'
        FROM public.turmas WHERE id = tid
        RETURNING id INTO mid;
      ELSIF i BETWEEN 11 AND 15 THEN
        INSERT INTO public.matriculas
          (aluno_id, turma_id, tipo, professor_id, tipo_pagamento,
           valor_matricula, matricula_forma_pagamento, parcelas, dia_vencimento,
           valor_mensal, valor_aula, status, data_inicio, observacao)
        SELECT aluno_ids[i], tid, 'turma', NULL, 'mensal',
               60, 'pix', NULL, 5,
               (SELECT valor_mensal FROM public.turmas WHERE id = tid)::numeric(10,2), 0,
               'ativa', dt, 'Mensalidade recorrente (seed)'
        FROM public.turmas WHERE id = tid
        RETURNING id INTO mid;
      ELSIF i BETWEEN 16 AND 23 THEN
        qtd := (CASE WHEN i % 3 = 0 THEN 12 WHEN i % 2 = 0 THEN 6 ELSE 1 END);
        INSERT INTO public.matriculas
          (aluno_id, turma_id, tipo, professor_id, tipo_pagamento,
           valor_matricula, matricula_forma_pagamento, valor_total, parcelas, dia_vencimento,
           valor_mensal, valor_aula, status, data_inicio,
           dia_semana, horario, observacao)
        VALUES (aluno_ids[i], NULL, 'individual', pid, 'parcelado',
                80, 'cartao', (280 + (i % 10) * 10)::numeric(10,2) * qtd, qtd, (CASE WHEN i % 2 = 0 THEN 10 ELSE 20 END),
                0, 0, 'ativa', dt,
                dias[(i % 6) + 1], (CASE WHEN i % 2 = 0 THEN '08:00' ELSE '09:00' END)::time,
                'Aluno VIP - carnê ' || qtd || 'x (seed)')
        RETURNING id INTO mid;
      ELSIF i BETWEEN 24 AND 26 THEN
        INSERT INTO public.matriculas
          (aluno_id, turma_id, tipo, professor_id, tipo_pagamento,
           valor_matricula, matricula_forma_pagamento, parcelas, dia_vencimento,
           valor_mensal, valor_aula, status, data_inicio,
           dia_semana, horario, observacao)
        VALUES (aluno_ids[i], NULL, 'individual', pid, 'mensal',
                50, 'dinheiro', NULL, 5,
                (280 + (i % 10) * 10)::numeric(10,2), 0, 'ativa', dt,
                dias[(i % 6) + 1], '10:00', 'Aluno VIP mensal (seed)')
        RETURNING id INTO mid;
      ELSE
        INSERT INTO public.matriculas
          (aluno_id, turma_id, tipo, professor_id, tipo_pagamento,
           valor_matricula, matricula_forma_pagamento, parcelas, dia_vencimento,
           valor_mensal, valor_aula, status, data_inicio,
           dia_semana, horario, observacao)
        VALUES (aluno_ids[i], NULL, 'individual', pid, 'avulsa',
                0, 'pix', NULL, 5,
                0, (90 + ((i % 3) * 15))::numeric(10,2), 'ativa', dt,
                dias[(i % 6) + 1], '11:00', 'Aula avulsa (seed)')
        RETURNING id INTO mid;
      END IF;
    END IF;

    -- ---------- Gera parcelas do carnê (estrutura do gerar_carne) ----------
    IF mid IS NOT NULL THEN
      SELECT tipo_pagamento, parcelas, valor_total, data_inicio, dia_vencimento, turma_id
        INTO rg_x, qtd, baseN, dt, vdia, tid
        FROM public.matriculas WHERE id = mid;
      IF rg_x = 'parcelado' AND qtd IS NOT NULL AND baseN > 0 THEN
        SELECT COALESCE(nome, 'Aluno VIP') INTO curso FROM public.turmas t
          JOIN public.matriculas m ON m.turma_id = t.id WHERE m.id = mid;
        IF curso IS NULL THEN curso := 'Aluno VIP'; END IF;
        dt := date_trunc('month', dt)::date;
        FOR p IN 0..qtd-1 LOOP
          comp := (dt + make_interval(months => p))::date;
          ven  := comp + (vdia - 1) * interval '1 day';
          parc := (CASE WHEN p = qtd - 1 THEN baseN - (qtd - 1) * round(baseN / qtd, 2) ELSE round(baseN / qtd, 2) END);
          INSERT INTO public.financeiro
            (aluno_id, matricula_id, tipo, descricao, valor, vencimento, competencia, status)
          SELECT aluno_ids[i], mid, 'mensalidade',
                 'Parcela ' || (p + 1) || '/' || qtd || ' - ' || curso,
                 parc, ven, comp, 'pendente'
          ON CONFLICT (matricula_id, competencia, tipo) WHERE tipo = 'mensalidade' DO NOTHING;
        END LOOP;
      END IF;
    END IF;
  END LOOP;

  RAISE NOTICE 'Seed concluído: professors=10, turmas=10, alunos=30, matriculas=30 (parcelas de carnê geradas).';
END $$;