-- BLOCO 10 - CHECAGEM FINAL (deve retornar 9 tabelas, 6 views, 12 funções)
-- ============================================================
SELECT
  (SELECT count(*) FROM pg_tables     WHERE schemaname = 'public' AND tablename IN
     ('usuarios','professores','alunos','turmas','matriculas','grade_conteudos',
      'conteudos_ministrados','desempenhos','financeiro'))      AS tabelas,
  (SELECT count(*) FROM pg_views      WHERE schemaname = 'public' AND viewname LIKE 'vw_%') AS views,
  (SELECT count(*) FROM pg_policies   WHERE schemaname = 'public') AS politicas,
  (SELECT count(*) FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
     WHERE n.nspname = 'public')                                 AS funcoes,
  (SELECT count(*) FROM pg_trigger t WHERE NOT t.tgisinternal)   AS triggers;
-- Resultado esperado: 9 tabelas | 6 views | 37 politicas | 12 funcoes | 5 triggers
