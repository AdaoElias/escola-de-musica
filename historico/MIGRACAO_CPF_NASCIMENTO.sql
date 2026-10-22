-- ============================================================
-- MIGRAÇÃO - CPF e Data de Nascimento em Professores e Alunos
-- Executar no Supabase > SQL Editor
-- ============================================================

ALTER TABLE public.professores
  ADD COLUMN IF NOT EXISTS cpf        TEXT,
  ADD COLUMN IF NOT EXISTS nascimento DATE;

ALTER TABLE public.alunos
  ADD COLUMN IF NOT EXISTS cpf        TEXT,
  ADD COLUMN IF NOT EXISTS nascimento DATE;