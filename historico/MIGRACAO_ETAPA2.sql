-- ============================================================
-- ETAPA 2 - Autenticação + RLS
-- Executar no Supabase > SQL Editor, na ordem apresentada.
-- ============================================================

-- 1. Vincula contas do Supabase Auth ao cadastro local
ALTER TABLE public.usuarios ADD COLUMN IF NOT EXISTS auth_uid uuid;
ALTER TABLE public.usuarios ADD CONSTRAINT usuarios_auth_uid_key UNIQUE (auth_uid);
ALTER TABLE public.usuarios ALTER COLUMN senha_hash DROP NOT NULL;

-- 2. Funções auxiliares usadas nas políticas RLS
CREATE OR REPLACE FUNCTION public.usuario_atual() RETURNS bigint
LANGUAGE sql STABLE AS $$
  SELECT u.id FROM public.usuarios u WHERE u.auth_uid = auth.uid();
$$;

CREATE OR REPLACE FUNCTION public.administrador_atual() RETURNS boolean
LANGUAGE sql STABLE AS $$
  SELECT EXISTS (
    SELECT 1 FROM public.usuarios u
    WHERE u.auth_uid = auth.uid() AND u.perfil = 'admin'
  );
$$;

CREATE OR REPLACE FUNCTION public.professor_atual() RETURNS bigint
LANGUAGE sql STABLE AS $$
  SELECT p.id FROM public.professores p
  JOIN public.usuarios u ON u.id = p.usuario_id
  WHERE u.auth_uid = auth.uid();
$$;

-- 3. Função de health check (acessível publicamente, sem expor dados)
CREATE OR REPLACE FUNCTION public.health_check() RETURNS text
LANGUAGE sql SECURITY DEFINER AS $$ SELECT 'ok'::text; $$;
GRANT EXECUTE ON FUNCTION public.health_check() TO anon, authenticated;

-- 4. Habilitar RLS em todas as tabelas
ALTER TABLE public.usuarios              ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.professores           ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.alunos                ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.turmas                ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.matriculas            ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.grade_conteudos       ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.conteudos_ministrados ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.desempenhos           ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.financeiro            ENABLE ROW LEVEL SECURITY;

-- 5. Políticas: USUARIOS (usuário vê a si; admin gerencia)
CREATE POLICY usuarios_select_self      ON public.usuarios FOR SELECT USING (auth_uid = auth.uid());
CREATE POLICY usuarios_admin_select     ON public.usuarios FOR SELECT USING (public.administrador_atual());
CREATE POLICY usuarios_admin_insert     ON public.usuarios FOR INSERT WITH CHECK (public.administrador_atual());
CREATE POLICY usuarios_admin_update     ON public.usuarios FOR UPDATE USING (public.administrador_atual());
CREATE POLICY usuarios_admin_delete     ON public.usuarios FOR DELETE USING (public.administrador_atual());

-- 6. Políticas: PROFESSORES (admin tudo; professor vê a si)
CREATE POLICY professores_select        ON public.professores FOR SELECT USING (public.administrador_atual() OR id = public.professor_atual());
CREATE POLICY professores_admin_insert  ON public.professores FOR INSERT WITH CHECK (public.administrador_atual());
CREATE POLICY professores_admin_update  ON public.professores FOR UPDATE USING (public.administrador_atual());
CREATE POLICY professores_admin_delete  ON public.professores FOR DELETE USING (public.administrador_atual());

-- 7. Políticas: TURMAS (admin tudo; professor vê as próprias)
CREATE POLICY turmas_select             ON public.turmas FOR SELECT USING (public.administrador_atual() OR professor_id = public.professor_atual());
CREATE POLICY turmas_admin_insert       ON public.turmas FOR INSERT WITH CHECK (public.administrador_atual());
CREATE POLICY turmas_admin_update       ON public.turmas FOR UPDATE USING (public.administrador_atual());
CREATE POLICY turmas_admin_delete       ON public.turmas FOR DELETE USING (public.administrador_atual());

-- 8. Políticas: ALUNOS (admin tudo; professor vê alunos vinculados às suas turmas/matrículas)
CREATE POLICY alunos_select             ON public.alunos FOR SELECT USING (
  public.administrador_atual() OR EXISTS (
    SELECT 1 FROM public.matriculas m
    WHERE m.aluno_id = alunos.id
      AND (m.professor_id = public.professor_atual()
        OR (SELECT t.professor_id FROM public.turmas t WHERE t.id = m.turma_id) = public.professor_atual())
  )
);
CREATE POLICY alunos_admin_insert       ON public.alunos FOR INSERT WITH CHECK (public.administrador_atual());
CREATE POLICY alunos_admin_update       ON public.alunos FOR UPDATE USING (public.administrador_atual());
CREATE POLICY alunos_admin_delete       ON public.alunos FOR DELETE USING (public.administrador_atual());

-- 9. Políticas: MATRÍCULAS
CREATE POLICY matriculas_select         ON public.matriculas FOR SELECT USING (
  public.administrador_atual() OR professor_id = public.professor_atual()
    OR (SELECT t.professor_id FROM public.turmas t WHERE t.id = matriculas.turma_id) = public.professor_atual()
);
CREATE POLICY matriculas_admin_insert   ON public.matriculas FOR INSERT WITH CHECK (public.administrador_atual());
CREATE POLICY matriculas_admin_update   ON public.matriculas FOR UPDATE USING (public.administrador_atual());
CREATE POLICY matriculas_admin_delete   ON public.matriculas FOR DELETE USING (public.administrador_atual());

-- 10. Políticas: GRADE_CONTEUDOS (qualquer usuário logado lê; admin edita)
CREATE POLICY grade_select              ON public.grade_conteudos FOR SELECT USING (auth.uid() IS NOT NULL);
CREATE POLICY grade_admin_insert        ON public.grade_conteudos FOR INSERT WITH CHECK (public.administrador_atual());
CREATE POLICY grade_admin_update        ON public.grade_conteudos FOR UPDATE USING (public.administrador_atual());
CREATE POLICY grade_admin_delete        ON public.grade_conteudos FOR DELETE USING (public.administrador_atual());

-- 11. Políticas: CONTEUDOS_MINISTRADOS (professor lança nas suas turmas/alunos)
CREATE POLICY cm_select ON public.conteudos_ministrados FOR SELECT USING (
  public.administrador_atual() OR professor_id = public.professor_atual()
    OR (SELECT t.professor_id FROM public.turmas t WHERE t.id = conteudos_ministrados.turma_id) = public.professor_atual()
    OR (SELECT m.professor_id FROM public.matriculas m WHERE m.id = conteudos_ministrados.matricula_id) = public.professor_atual()
);
CREATE POLICY cm_insert ON public.conteudos_ministrados FOR INSERT WITH CHECK (
  public.administrador_atual() OR professor_id = public.professor_atual()
    OR (SELECT t.professor_id FROM public.turmas t WHERE t.id = turma_id) = public.professor_atual()
    OR (SELECT m.professor_id FROM public.matriculas m WHERE m.id = matricula_id) = public.professor_atual()
);
CREATE POLICY cm_update ON public.conteudos_ministrados FOR UPDATE USING (
  public.administrador_atual() OR professor_id = public.professor_atual()
    OR (SELECT t.professor_id FROM public.turmas t WHERE t.id = conteudos_ministrados.turma_id) = public.professor_atual()
    OR (SELECT m.professor_id FROM public.matriculas m WHERE m.id = conteudos_ministrados.matricula_id) = public.professor_atual()
);
CREATE POLICY cm_delete ON public.conteudos_ministrados FOR DELETE USING (
  public.administrador_atual() OR professor_id = public.professor_atual()
    OR (SELECT t.professor_id FROM public.turmas t WHERE t.id = conteudos_ministrados.turma_id) = public.professor_atual()
    OR (SELECT m.professor_id FROM public.matriculas m WHERE m.id = conteudos_ministrados.matricula_id) = public.professor_atual()
);

-- 12. Políticas: DESEMPENHOS (professor avalia alunos que ensina)
CREATE POLICY desempenhos_select ON public.desempenhos FOR SELECT USING (
  public.administrador_atual() OR EXISTS (
    SELECT 1 FROM public.conteudos_ministrados cm
    WHERE cm.id = desempenhos.conteudo_id
      AND (cm.professor_id = public.professor_atual()
        OR (SELECT t.professor_id FROM public.turmas t WHERE t.id = cm.turma_id) = public.professor_atual()
        OR (SELECT m.professor_id FROM public.matriculas m WHERE m.id = cm.matricula_id) = public.professor_atual())
  )
);
CREATE POLICY desempenhos_insert ON public.desempenhos FOR INSERT WITH CHECK (
  public.administrador_atual() OR EXISTS (
    SELECT 1 FROM public.conteudos_ministrados cm
    WHERE cm.id = conteudo_id
      AND (cm.professor_id = public.professor_atual()
        OR (SELECT t.professor_id FROM public.turmas t WHERE t.id = cm.turma_id) = public.professor_atual()
        OR (SELECT m.professor_id FROM public.matriculas m WHERE m.id = cm.matricula_id) = public.professor_atual())
  )
);
CREATE POLICY desempenhos_update ON public.desempenhos FOR UPDATE USING (
  public.administrador_atual() OR EXISTS (
    SELECT 1 FROM public.conteudos_ministrados cm
    WHERE cm.id = desempenhos.conteudo_id
      AND (cm.professor_id = public.professor_atual()
        OR (SELECT t.professor_id FROM public.turmas t WHERE t.id = cm.turma_id) = public.professor_atual()
        OR (SELECT m.professor_id FROM public.matriculas m WHERE m.id = cm.matricula_id) = public.professor_atual())
  )
);
CREATE POLICY desempenhos_delete ON public.desempenhos FOR DELETE USING (
  public.administrador_atual() OR EXISTS (
    SELECT 1 FROM public.conteudos_ministrados cm
    WHERE cm.id = desempenhos.conteudo_id
      AND (cm.professor_id = public.professor_atual()
        OR (SELECT t.professor_id FROM public.turmas t WHERE t.id = cm.turma_id) = public.professor_atual()
        OR (SELECT m.professor_id FROM public.matriculas m WHERE m.id = cm.matricula_id) = public.professor_atual())
  )
);

-- 13. Políticas: FINANCEIRO (exclusivo do Admin)
CREATE POLICY financeiro_admin_select ON public.financeiro FOR SELECT USING (public.administrador_atual());
CREATE POLICY financeiro_admin_insert ON public.financeiro FOR INSERT WITH CHECK (public.administrador_atual());
CREATE POLICY financeiro_admin_update ON public.financeiro FOR UPDATE USING (public.administrador_atual());
CREATE POLICY financeiro_admin_delete ON public.financeiro FOR DELETE USING (public.administrador_atual());