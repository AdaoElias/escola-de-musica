-- ============================================================
-- FIX RLS - "stack depth limit exceeded" ao salvar professor
-- Executar no Supabase > SQL Editor
--
-- Causa: as funções auxiliares consultam usuarios/professores e
-- essas consultas passam pelas políticas RLS das próprias tabelas,
-- que chamam as mesmas funções de novo (recursão infinita).
-- Solução: torná-las SECURITY DEFINER (rodam como dono das tabelas,
-- ignorando RLS) -> sem recursão. Continuam seguras: apenas
-- identificam o usuário atual com base no próprio auth.uid().
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