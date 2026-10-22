-- BLOCO 5 - FUNÇÕES AUXILIARES DE RLS
-- SECURITY DEFINER: sem isso, a policy da própria tabela chama a função
-- de novo (recursão) e o PostgreSQL estoura "stack depth limit exceeded".
-- ============================================================

CREATE OR REPLACE FUNCTION public.usuario_atual() RETURNS bigint
LANGUAGE sql STABLE SECURITY DEFINER
SET search_path = public AS $$
  SELECT u.id FROM public.usuarios u WHERE u.auth_uid = auth.uid();
$$;

CREATE OR REPLACE FUNCTION public.administrador_atual() RETURNS boolean
LANGUAGE sql STABLE SECURITY DEFINER
SET search_path = public AS $$
  SELECT EXISTS (
    SELECT 1 FROM public.usuarios u
    WHERE u.auth_uid = auth.uid() AND u.perfil = 'admin'
  );
$$;

CREATE OR REPLACE FUNCTION public.professor_atual() RETURNS bigint
LANGUAGE sql STABLE SECURITY DEFINER
SET search_path = public AS $$
  SELECT p.id FROM public.professores p
  JOIN public.usuarios u ON u.id = p.usuario_id
  WHERE u.auth_uid = auth.uid();
$$;

-- Health check (acessível publicamente, sem expor dados)
CREATE OR REPLACE FUNCTION public.health_check() RETURNS text
LANGUAGE sql SECURITY DEFINER AS $$ SELECT 'ok'::text; $$;
GRANT EXECUTE ON FUNCTION public.health_check() TO anon, authenticated;


-- ============================================================
