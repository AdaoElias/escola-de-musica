-- ============================================================
-- MIGRAÇÃO - Endereço em Professores e Alunos
-- Executar no Supabase > SQL Editor
-- ============================================================

ALTER TABLE public.professores
  ADD COLUMN IF NOT EXISTS endereco TEXT,
  ADD COLUMN IF NOT EXISTS bairro   TEXT,
  ADD COLUMN IF NOT EXISTS cidade   TEXT,
  ADD COLUMN IF NOT EXISTS cep      TEXT;

ALTER TABLE public.alunos
  ADD COLUMN IF NOT EXISTS endereco TEXT,
  ADD COLUMN IF NOT EXISTS bairro   TEXT,
  ADD COLUMN IF NOT EXISTS cidade   TEXT,
  ADD COLUMN IF NOT EXISTS cep      TEXT;