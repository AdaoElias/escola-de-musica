-- BLOCO 6 - RLS E POLÍTICAS
-- ============================================================

-- 6.1 Habilitar RLS em todas as tabelas
ALTER TABLE public.usuarios               ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.professores            ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.alunos                 ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.turmas                 ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.matriculas             ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.grade_conteudos        ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.conteudos_ministrados  ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.desempenhos            ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.financeiro             ENABLE ROW LEVEL SECURITY;

-- 6.2 USUARIOS (usuário vê a si; admin gerencia)
DROP POLICY IF EXISTS usuarios_select_self   ON public.usuarios;
DROP POLICY IF EXISTS usuarios_admin_select  ON public.usuarios;
DROP POLICY IF EXISTS usuarios_admin_insert  ON public.usuarios;
DROP POLICY IF EXISTS usuarios_admin_update  ON public.usuarios;
DROP POLICY IF EXISTS usuarios_admin_delete  ON public.usuarios;
CREATE POLICY usuarios_select_self      ON public.usuarios FOR SELECT USING (auth_uid = auth.uid());
CREATE POLICY usuarios_admin_select     ON public.usuarios FOR SELECT USING (public.administrador_atual());
CREATE POLICY usuarios_admin_insert     ON public.usuarios FOR INSERT WITH CHECK (public.administrador_atual());
CREATE POLICY usuarios_admin_update     ON public.usuarios FOR UPDATE USING (public.administrador_atual());
CREATE POLICY usuarios_admin_delete     ON public.usuarios FOR DELETE USING (public.administrador_atual());

-- 6.3 PROFESSORES (admin tudo; professor vê a si)
DROP POLICY IF EXISTS professores_select       ON public.professores;
DROP POLICY IF EXISTS professores_admin_insert ON public.professores;
DROP POLICY IF EXISTS professores_admin_update ON public.professores;
DROP POLICY IF EXISTS professores_admin_delete ON public.professores;
CREATE POLICY professores_select       ON public.professores FOR SELECT USING (public.administrador_atual() OR id = public.professor_atual());
CREATE POLICY professores_admin_insert ON public.professores FOR INSERT WITH CHECK (public.administrador_atual());
CREATE POLICY professores_admin_update ON public.professores FOR UPDATE USING (public.administrador_atual());
CREATE POLICY professores_admin_delete ON public.professores FOR DELETE USING (public.administrador_atual());

-- 6.4 TURMAS (admin tudo; professor vê as próprias)
DROP POLICY IF EXISTS turmas_select       ON public.turmas;
DROP POLICY IF EXISTS turmas_admin_insert ON public.turmas;
DROP POLICY IF EXISTS turmas_admin_update ON public.turmas;
DROP POLICY IF EXISTS turmas_admin_delete ON public.turmas;
CREATE POLICY turmas_select       ON public.turmas FOR SELECT USING (public.administrador_atual() OR professor_id = public.professor_atual());
CREATE POLICY turmas_admin_insert ON public.turmas FOR INSERT WITH CHECK (public.administrador_atual());
CREATE POLICY turmas_admin_update ON public.turmas FOR UPDATE USING (public.administrador_atual());
CREATE POLICY turmas_admin_delete ON public.turmas FOR DELETE USING (public.administrador_atual());

-- 6.5 ALUNOS (admin tudo; professor vê alunos vinculados às suas turmas/matrículas)
DROP POLICY IF EXISTS alunos_select       ON public.alunos;
DROP POLICY IF EXISTS alunos_admin_insert ON public.alunos;
DROP POLICY IF EXISTS alunos_admin_update ON public.alunos;
DROP POLICY IF EXISTS alunos_admin_delete ON public.alunos;
CREATE POLICY alunos_select       ON public.alunos FOR SELECT USING (
  public.administrador_atual() OR EXISTS (
    SELECT 1 FROM public.matriculas m
    WHERE m.aluno_id = alunos.id
      AND (m.professor_id = public.professor_atual()
        OR (SELECT t.professor_id FROM public.turmas t WHERE t.id = m.turma_id) = public.professor_atual())
  )
);
CREATE POLICY alunos_admin_insert ON public.alunos FOR INSERT WITH CHECK (public.administrador_atual());
CREATE POLICY alunos_admin_update ON public.alunos FOR UPDATE USING (public.administrador_atual());
CREATE POLICY alunos_admin_delete ON public.alunos FOR DELETE USING (public.administrador_atual());

-- 6.6 MATRÍCULAS
DROP POLICY IF EXISTS matriculas_select       ON public.matriculas;
DROP POLICY IF EXISTS matriculas_admin_insert ON public.matriculas;
DROP POLICY IF EXISTS matriculas_admin_update ON public.matriculas;
DROP POLICY IF EXISTS matriculas_admin_delete ON public.matriculas;
CREATE POLICY matriculas_select       ON public.matriculas FOR SELECT USING (
  public.administrador_atual() OR professor_id = public.professor_atual()
    OR (SELECT t.professor_id FROM public.turmas t WHERE t.id = matriculas.turma_id) = public.professor_atual()
);
CREATE POLICY matriculas_admin_insert ON public.matriculas FOR INSERT WITH CHECK (public.administrador_atual());
CREATE POLICY matriculas_admin_update ON public.matriculas FOR UPDATE USING (public.administrador_atual());
CREATE POLICY matriculas_admin_delete ON public.matriculas FOR DELETE USING (public.administrador_atual());

-- 6.7 GRADE_CONTEUDOS (qualquer usuário logado lê; admin edita)
DROP POLICY IF EXISTS grade_select       ON public.grade_conteudos;
DROP POLICY IF EXISTS grade_admin_insert ON public.grade_conteudos;
DROP POLICY IF EXISTS grade_admin_update ON public.grade_conteudos;
DROP POLICY IF EXISTS grade_admin_delete ON public.grade_conteudos;
CREATE POLICY grade_select       ON public.grade_conteudos FOR SELECT USING (auth.uid() IS NOT NULL);
CREATE POLICY grade_admin_insert ON public.grade_conteudos FOR INSERT WITH CHECK (public.administrador_atual());
CREATE POLICY grade_admin_update ON public.grade_conteudos FOR UPDATE USING (public.administrador_atual());
CREATE POLICY grade_admin_delete ON public.grade_conteudos FOR DELETE USING (public.administrador_atual());

-- 6.8 CONTEUDOS_MINISTRADOS (professor lança nas suas turmas/alunos)
DROP POLICY IF EXISTS cm_select ON public.conteudos_ministrados;
DROP POLICY IF EXISTS cm_insert ON public.conteudos_ministrados;
DROP POLICY IF EXISTS cm_update ON public.conteudos_ministrados;
DROP POLICY IF EXISTS cm_delete ON public.conteudos_ministrados;
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

-- 6.9 DESEMPENHOS (professor avalia apenas alunos que ensina)
DROP POLICY IF EXISTS desempenhos_select ON public.desempenhos;
DROP POLICY IF EXISTS desempenhos_insert ON public.desempenhos;
DROP POLICY IF EXISTS desempenhos_update ON public.desempenhos;
DROP POLICY IF EXISTS desempenhos_delete ON public.desempenhos;
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

-- 6.10 FINANCEIRO (exclusivo do Admin)
DROP POLICY IF EXISTS financeiro_admin_select ON public.financeiro;
DROP POLICY IF EXISTS financeiro_admin_insert ON public.financeiro;
DROP POLICY IF EXISTS financeiro_admin_update ON public.financeiro;
DROP POLICY IF EXISTS financeiro_admin_delete ON public.financeiro;
CREATE POLICY financeiro_admin_select ON public.financeiro FOR SELECT USING (public.administrador_atual());
CREATE POLICY financeiro_admin_insert ON public.financeiro FOR INSERT WITH CHECK (public.administrador_atual());
CREATE POLICY financeiro_admin_update ON public.financeiro FOR UPDATE USING (public.administrador_atual());
CREATE POLICY financeiro_admin_delete ON public.financeiro FOR DELETE USING (public.administrador_atual());


-- ============================================================
