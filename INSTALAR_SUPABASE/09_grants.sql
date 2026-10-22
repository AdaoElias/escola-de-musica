-- BLOCO 9 - GRANTS
-- ============================================================

GRANT USAGE ON SCHEMA public TO anon, authenticated, service_role;
GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA public TO authenticated;
GRANT USAGE, SELECT ON ALL SEQUENCES IN SCHEMA public TO authenticated;

-- 9.1 Revogar o EXECUTE das funções de negócio para o visitante sem login.
--     Atenção: revogar de PUBLIC não basta no Supabase. O Supabase dá, por padrão,
--     `GRANT ALL ON ALL FUNCTIONS IN SCHEMA public TO anon, authenticated` E
--     `ALTER DEFAULT PRIVILEGES ... GRANT ALL ON FUNCTIONS TO anon` — o papel `anon`
--     tem um privilégio EXPLICITO que sobrevive ao REVOKE ... FROM PUBLIC.
--     Por isso revogamos dos DOIS (PUBLIC e anon).
REVOKE ALL ON FUNCTION public.cpf_valido(text) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.gerar_mensalidades(date) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.gerar_carne(bigint) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.gerar_financeiro_avulsa() FROM PUBLIC;
REVOKE ALL ON FUNCTION public.gerar_financeiro_matricula() FROM PUBLIC;
REVOKE ALL ON FUNCTION public.cancelar_financeiro_avulsa() FROM PUBLIC;
REVOKE ALL ON FUNCTION public.bloquear_inativacao_professor() FROM PUBLIC;
REVOKE ALL ON FUNCTION public.exigir_professor_ativo_na_turma() FROM PUBLIC;

REVOKE ALL ON FUNCTION public.cpf_valido(text) FROM anon;
REVOKE ALL ON FUNCTION public.gerar_mensalidades(date) FROM anon;
REVOKE ALL ON FUNCTION public.gerar_carne(bigint) FROM anon;
REVOKE ALL ON FUNCTION public.gerar_financeiro_avulsa() FROM anon;
REVOKE ALL ON FUNCTION public.gerar_financeiro_matricula() FROM anon;
REVOKE ALL ON FUNCTION public.cancelar_financeiro_avulsa() FROM anon;
REVOKE ALL ON FUNCTION public.bloquear_inativacao_professor() FROM anon;
REVOKE ALL ON FUNCTION public.exigir_professor_ativo_na_turma() FROM anon;

-- 9.2 Conceder EXECUTE apenas a quem está autenticado.
--     Inclui as funções de TRIGGER (disparadas por INSERT/UPDATE de quem está
--     logado): o papel que executa a ação precisa de EXECUTE nelas.
GRANT EXECUTE ON FUNCTION public.cpf_valido(text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.gerar_mensalidades(date) TO authenticated;
GRANT EXECUTE ON FUNCTION public.gerar_carne(bigint) TO authenticated;
GRANT EXECUTE ON FUNCTION public.gerar_financeiro_avulsa() TO authenticated;
GRANT EXECUTE ON FUNCTION public.gerar_financeiro_matricula() TO authenticated;
GRANT EXECUTE ON FUNCTION public.cancelar_financeiro_avulsa() TO authenticated;
GRANT EXECUTE ON FUNCTION public.bloquear_inativacao_professor() TO authenticated;
GRANT EXECUTE ON FUNCTION public.exigir_professor_ativo_na_turma() TO authenticated;

-- 9.3 As funções de RLS (usuario_atual, administrador_atual, professor_atual)
--     PRECISAM continuar executáveis por QUALQUER papel, inclusive `anon`:
--     são elas que as políticas de RLS chamam ao avaliar cada linha. Se o
--     papel que consulta não puder chamá-las, a consulta falha com "permissão
--     negada" em vez de devolver lista vazia. Elas são inofensivas para quem
--     não está logado (auth.uid() é NULL → devolvem NULL/false).
GRANT EXECUTE ON FUNCTION public.usuario_atual() TO anon, authenticated;
GRANT EXECUTE ON FUNCTION public.administrador_atual() TO anon, authenticated;
GRANT EXECUTE ON FUNCTION public.professor_atual() TO anon, authenticated;


-- ============================================================
