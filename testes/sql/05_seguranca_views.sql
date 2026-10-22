-- Seguranca: as views nao podem vazar dados para o papel `anon` (visitante
-- sem login) e as RPCs de financeiro nao podem ser executadas por `anon`.
--
-- Contexto: no Supabase, `anon` tem SELECT por padrao em ALL TABLES (inclusive
-- nas views) e o RLS e a unica protecao. View nao tem RLS e e executada com os
-- privilegios do dono (superusuario) -> sem `security_invoker = true`, qualquer
-- visitante leria nomes de alunos, inadimplencia e financeiro.
--
-- Este teste reproduz o padrao do Supabase (GRANT SELECT ... TO anon) e
-- verifica que o RLS segura.
--
-- O mock_auth.sql ja deixa `anon` com EXECUTE nas funcoes (ALTER DEFAULT
-- PRIVILEGES, como o Supabase faz). Assim, o BLOCO 9 do INSTALAR.sql precisa
-- REVOKAR de PUBLIC **e** de anon para o teste passar — que e o cenario real.

-- 1) As 6 views de relatorio devem ter security_invoker = true (PostgreSQL 15+)
DO $$
DECLARE
  n     INTEGER;
  sem   TEXT;
BEGIN
  IF current_setting('server_version_num')::int < 150000 THEN
    RAISE NOTICE 'PostgreSQL < 15: security_invoker indisponivel, verificacao ignorada.';
    RETURN;
  END IF;

  SELECT count(*) INTO n FROM pg_class c JOIN pg_namespace ns ON ns.oid = c.relnamespace
   WHERE ns.nspname = 'public' AND c.relkind = 'v'
     AND (c.reloptions IS NULL OR NOT (c.reloptions @> ARRAY['security_invoker=true']));
  IF n > 0 THEN
    SELECT string_agg(relname, ', ' ORDER BY relname) INTO sem
    FROM (SELECT c.relname FROM pg_class c JOIN pg_namespace ns ON ns.oid = c.relnamespace
           WHERE ns.nspname = 'public' AND c.relkind = 'v'
             AND (c.reloptions IS NULL OR NOT (c.reloptions @> ARRAY['security_invoker=true']))) s;
    RAISE EXCEPTION 'FALHOU: % view(s) sem security_invoker: %', n, sem;
  END IF;
END $$;

-- 2) `anon` NAO pode executar as RPCs de financeiro
DO $$
DECLARE
  f TEXT;
BEGIN
  FOREACH f IN ARRAY ARRAY['gerar_mensalidades(date)','gerar_carne(bigint)','cpf_valido(text)'] LOOP
    IF has_function_privilege('anon', 'public.' || f, 'EXECUTE') THEN
      RAISE EXCEPTION 'FALHOU: anon pode executar public.%', f;
    END IF;
  END LOOP;
END $$;

-- 3) `anon` PRECISA poder executar as funcoes de RLS, senao as politicas
--    quebram com "permissao negada" em vez de devolver lista vazia
DO $$
DECLARE
  f TEXT;
BEGIN
  FOREACH f IN ARRAY ARRAY['usuario_atual()','administrador_atual()','professor_atual()'] LOOP
    IF NOT has_function_privilege('anon', 'public.' || f, 'EXECUTE') THEN
      RAISE EXCEPTION 'FALHOU: anon nao pode executar public.% (as politicas de RLS dependem dela)', f;
    END IF;
  END LOOP;
END $$;

-- 4) Reproduzir o padrao do Supabase e conferir que o anon nao ve nada
GRANT SELECT ON ALL TABLES IN SCHEMA public TO anon;
SET ROLE anon;
DO $$
DECLARE
  v TEXT;
  n BIGINT;
BEGIN
  FOREACH v IN ARRAY ARRAY['vw_inadimplentes','vw_financeiro_resumo','vw_desempenho_aluno',
                           'vw_desempenho_turma','vw_progresso_turma','vw_progresso_aluno'] LOOP
    EXECUTE format('SELECT count(*) FROM public.%I', v) INTO n;
    IF n > 0 THEN
      RAISE EXCEPTION 'FALHOU: anon enxerga % linhas em public.%', n, v;
    END IF;
  END LOOP;

  SELECT count(*) INTO n FROM public.alunos;
  IF n > 0 THEN RAISE EXCEPTION 'FALHOU: anon enxerga % linhas em public.alunos', n; END IF;

  SELECT count(*) INTO n FROM public.financeiro;
  IF n > 0 THEN RAISE EXCEPTION 'FALHOU: anon enxerga % linhas em public.financeiro', n; END IF;
END $$;
RESET ROLE;

-- 5) O anon so pode executar 4 funcoes: health_check (monitoramento) e as 3
--    auxiliares de RLS (usuario_atual, administrador_atual, professor_atual),
--    que as politicas precisam conseguir chamar. Nenhuma RPC de negocio.
DO $$
DECLARE
  n INTEGER;
BEGIN
  SELECT count(*) INTO n
    FROM pg_proc p JOIN pg_namespace ns ON ns.oid = p.pronamespace
   WHERE ns.nspname = 'public'
     AND has_function_privilege('anon', p.oid, 'EXECUTE');
  IF n <> 4 THEN
    RAISE EXCEPTION 'FALHOU: anon pode executar % funcao(oes) de public (esperado 4: health_check + 3 auxiliares de RLS)', n;
  END IF;
END $$;
