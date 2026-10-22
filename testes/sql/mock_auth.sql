-- Ambiente de teste local: emula o que o Supabase já oferece
-- (schema auth com auth.uid() e os papéis anon/authenticated/service_role).
CREATE SCHEMA IF NOT EXISTS auth;

-- auth.uid() no Supabase devolve o 'sub' do JWT da requisição. O mock usa o
-- mesmo mecanismo (GUC de sessão): quem define o GUC é o "usuário logado".
-- Importante: o 03_vencimento_carne.sql simula o admin assim, em vez de
-- redefinir auth.uid() globalmente — antes, o `anon` passava a "ser admin" e
-- o teste de segurança (05) acusava vazamento onde não havia.
CREATE OR REPLACE FUNCTION auth.uid() RETURNS uuid LANGUAGE sql STABLE AS $$
  SELECT NULLIF(current_setting('request.jwt.claim.sub', true), '')::uuid $$;

DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'anon') THEN CREATE ROLE anon NOLOGIN; END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'authenticated') THEN CREATE ROLE authenticated NOLOGIN; END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'service_role') THEN CREATE ROLE service_role NOLOGIN; END IF;
END $$;
GRANT USAGE ON SCHEMA public TO anon, authenticated, service_role;

-- O Supabase entrega o schema public já com privilégio de EXECUTE para `anon` e
-- `authenticated` (GRANT ... ON ALL FUNCTIONS + ALTER DEFAULT PRIVILEGES).
-- O mock reproduz isso de propósito: as funções nascem executáveis pelo `anon`
-- e quem precisa negar é o REVOKE do BLOCO 9 do INSTALAR.sql. Sem esta linha,
-- o teste de segurança passaria sem exercitar o cenário real.
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT EXECUTE ON FUNCTIONS TO anon, authenticated;
