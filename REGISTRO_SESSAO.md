# Registro da Sessão — Escola de Música

> Data: 21/09/2026 · Continuidade prevista para a próxima sessão.

Este documento registra tudo o que foi pedido, decidido e implementado nesta sessão, além dos problemas resolvidos, para retomada sem perda de contexto.

---

## 1. Resumo do objetivo

Criar um **aplicativo web para gestão de uma escola de música** com turmas coletivas e aulas individuais: cadastro de professores e alunos, grade e conteúdo programático, financeiro (a receber/recebido, mensal + avulsa), turmas independentes, gráficos de desempenho por turma e por aluno.

**Stack escolhida:**
- Frontend: **HTML + CSS + JavaScript** (puro, sem framework)
- Backend: **Netlify Functions** (Node.js, plano gratuito)
- Banco: **Supabase / PostgreSQL** (plano gratuito) + **Supabase Auth**
- Git: repositório **GitHub** `AdaoElias/escola-de-musica`

---

## 2. Levantamento inicial (pedido do usuário)

Pesquisa sobre os 3 apps mais usados para gestão de cursos livres, com tecnologias (backend/frontend/banco) e prós/contras:

| Plataforma | Backend | Frontend | Banco | Vantagens | Desvantagens |
|---|---|---|---|---|---|
| **Moodle** | PHP (8.2+), plugins | PHP/Mustache, jQuery, Bootstrap | MySQL/MariaDB/PostgreSQL | Gratuito, open source, customizável | Exige time técnico, UI datada |
| **Google Classroom** | Proprietário (GCP), REST API | Proprietário | Proprietário | Zero manutenção, gratuito | Fechado, sem customização |
| **Canvas LMS** | Ruby on Rails, GraphQL+REST | React + TypeScript | PostgreSQL, Redis | UX moderna, escala | Caro, complexo p/ pequena escala |

**Decisão:** construir sistema próprio (escolinha de música), hospedagem gratuita (Netlify + Supabase).

---

## 3. Requisitos confirmados pelo usuário (Etapa 0)

1. **Perfis:** Admin (tudo) e Professor (lança aulas/conteúdos das suas turmas/alunos; sem acesso ao financeiro).
2. **Cobrança:** mensal por padronagem + **aula avulsa** avaliada (implementada somente para matrículas individuais, na fase 2).
3. **Grade:** única e padrão para todos; quem é individual apenas avança mais rápido (progresso independente por turma/matrícula).

**Arquivos entregues (Etapa 0):**
- `REQUISITOS.md` — RF/RNF, regras de negócio, permissões, ERD (Mermaid), specs das tabelas
- `SCHEMA.sql` — 9 tabelas + views de relatório + índices (PostgreSQL)

---

## 4. Etapa 1 — Ambiente no ar (concluída)

**Feito:**
- Estrutura do projeto: `public/` (site), `functions/` (Netlify Functions), `netlify.toml`, `.env.example`, `.gitignore`, `package.json` (netlify-cli + @supabase/supabase-js)
- `git init` + commits no GitHub
- Redeploy automático Netlify a partir do GitHub
- Supabase: `SCHEMA.sql` aplicado | Env vars: `SUPABASE_URL` e `SUPABASE_PUBLISHABLE_KEY`
- Functions funcionando: `/api/hello`, `/api/health` → `{"db":"conectado"}`

**Problemas resolvidos:**
- Site com 401 em tudo → desativar **Site Protection (Password)** no Netlify
- Env vars não chegavam: **bug meu** — o código montava `{url: 'definida'}` em vez do valor real (corrigido)
- URL do Supabase colada com `/rest/v1/` ou sem `https://` → normalizar para `https://<projeto>.supabase.co`

**Ponteiros de credenciais (NÃO colar valores aqui):**
- `.env.local` (local, ignorado pelo git)
- Netlify → Site configuration → Environment variables

---

## 5. Etapa 2 — Autenticação + RLS + CRUD Professores (concluída)

**Feito:**
- `functions/client-config.js` → entrega URL+chave publishable para o navegador
- `public/js/supabase.js`, `public/js/auth.js` (login/logout/guarda de rotas/perfil)
- `public/index.html` = tela de login · `public/app.html` = painel/menu
- `public/professores.html` + `public/js/professores.js` (CRUD)
- `MIGRACAO_ETAPA2.sql` → funcões `usuario_atual/administrador_atual/professor_atual`, `health_check` (RPC), **RLS em todas as tabelas** (admin vê tudo; professor só o que é dele; financeiro só admin)

**Problemas resolvidos:**
- `senha_hash NOT NULL` bloqueava vinculo do admin → `alter table usuarios alter column senha_hash drop not null`
- **Login 400 com senha certa** → bug no `auth.js`: enviava `{email, senha}` mas o Supabase exige `{email, password}` → corrigido
- Conta era criada "para teste" com senha digitada errada → resolvido com novo usuário (o Auth estava OK, confirmado por teste direto na API)

**Como vincular um user do Auth ao perfil admin (SQL):**
```sql
insert into public.usuarios (auth_uid, nome, email, perfil)
select au.id, coalesce(nullif(au.raw_user_meta_data->>'full_name',''), 'Administrador'), au.email, 'admin'
from auth.users au
where au.email = 'SEU_EMAIL'
on conflict (auth_uid) do nothing;
```

---

## 6. Etapa 3 — Alunos, Turmas e Matrículas (concluída)

Páginas novas (CRUD completos no menu):
- **Alunos** — `public/alunos.html` + `public/js/alunos.js`
- **Turmas** — `public/turmas.html` + `public/js/turmas.js` (professor responsável, dia/horário, valor mensal, encerrar)
- **Matrículas** — `public/matriculas.html` + `public/js/matriculas.js`
  - tipo **turma** (busca valor da turma) ou **individual** (professor + valor)
  - pagamento **mensal** ou **avulsa** (avulsa só individual)
- CSS atualizado (`select`, `time`, `date`, grade de 2 colunas)

---

## 7. Estado atual do projeto

Repositório: https://github.com/AdaoElias/escola-de-musica
Site: https://escola-demusica.netlify.app
Banco: Supabase (tabelas do SCHEMA.sql + migration RLS aplicadas)

```
public/            → index(login), app(painel), professores, alunos, turmas, matriculas
public/js/         → supabase.js, auth.js, professores.js, alunos.js, turmas.js, matriculas.js
public/css/style.css
functions/         → hello.js, health.js, client-config.js
netlify.toml, .env.example, .env.local (não versionado)
REQUISITOS.md, SCHEMA.sql, MIGRACAO_ETAPA2.sql
```

**Conta de teste ativa:** `teste@escola.com` (admin). Sugestão: trocar pela conta definitiva.

---

## 8. Próximos passos

- ✅ **Etapa 0** requesitos/diagrama
- ✅ **Etapa 1** ambiente (GitHub/Supabase/Netlify)
- ✅ **Etapa 2** login + RLS + professores
- ✅ **Etapa 3** alunos + turmas + matrículas
- ⏭️ **Etapa 4** Grade de conteúdos (`grade_conteudos`) + lançamento de aulas (`conteudos_ministrados`) por turma/individual com progresso e evolução (%), desempenho por aluno (`desempenhos`)
- ⏭️ **Etapa 5** Financeiro (mensal primeiro; avulsa = geração automática ao lançar aula) + inadimplência
- ⏭️ **Etapa 6** Gráficos: desempenho da turma, por aluno, financeiro (views `vw_*` já prontas no SCHEMA.sql)

**Pendências anotadas:**
- Excluir/ajustar conta `teste@escola.com` e criar e-mail definitivo de admin (ou manter, se preferir)
- Avaliar liberação: professor acessa só com conta vinculada (`professores.usuario_id`)
- Views `vw_desempenho_turma/vw_desempenho_aluno/vw_financeiro_resumo/vw_inadimplentes` já existem no banco → consumir na Etapa 6