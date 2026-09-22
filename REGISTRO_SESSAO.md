# Registro da Sessão — Escola de Música

> Data: 21/09/2026 (atualizado 22/09/2026) · Continuidade prevista para a próxima sessão.

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

## 7. Etapa 4 — Grade, Aulas e Progresso (concluída)

**Páginas novas:**
- **Grade de Conteúdos** — `public/grade.html` + `public/js/grade.js`
  - CRUD da grade padrão (ordem, título, descrição, módulo, nível, tempo estimado em minutos, ativo)
  - Admin cria/edita/exclui; professor só visualiza (permite lançar aulas referenciando a grade)
- **Aulas** — `public/aulas.html` + `public/js/aulas.js`
  - Lançamento de aula para **turma** ou **matrícula individual** (título/descrição, item da grade opcional, evolução da turma %)
  - Professor responsável é preenchido automaticamente em cada tipo
  - Desempenho por aluno dentro da turma (botão **Avaliar**) e desempenho inline na aula individual (RF21)
  - Seção **Progresso da grade** consumindo as views (ministrados vs. total, com barra) (RF22)

**Banco:** `MIGRACAO_ETAPA4.sql` → ajustes **NÃO aplicados ainda**:
- `vw_progresso_turma` e `vw_progresso_aluno` (percentual da grade por turma/matrícula individual)
- ⚠️ **Executar `MIGRACAO_ETAPA4.sql` no Supabase > SQL Editor** para a seção de progresso funcionar
- Tabelas `grade_conteudos`, `conteudos_ministrados`, `desempenhos` e suas RLS já existiam (SCHEMA.sql + MIGRACAO_ETAPA2.sql), nada a aplicar nesses pontos

**Menus atualizados:** `Grade` e `Aulas` viraram links reais em todas as páginas; tile no painel atualizado.

**Notas para teste:**
- Professor vinculado a turma/matrícula consegue lançar aulas nelas (RLS `cm_insert`/`desempenhos_insert`)
- Evolução e desempenho são 0–100 (RN05)
- Ao lançar aula individual, o campo desempenho/avaliação grava em `desempenhos` (upsert por `aluno_id,conteudo_id`)

---

## 8. Redesign — Dashboard + base de design (nova)

Motivo: forma dos formulários e falta de dashboard na home. Baseado em pesquisa de boas práticas (NN/g, UX Collective): coluna única, labels acima, validação com feedback, KPIs no topo, alertas de atenção, cor = estado.

**Dashboard (`app.html`/`app.js`)**
- KPIs no topo: Alunos ativos, Professores ativos, Turmas ativas, Matrículas ativas (mais grandes)
- Admin vê ainda: **A receber no mês** e **Inadimplentes** (consome `vw_financeiro_resumo` e `vw_inadimplentes`)
- Bloco **Precisa de atenção**: turmas sem aulas, aulas sem item da grade, matrículas fora de atividade, alunos inativos, inadimplentes (detalhe por aluno)
- Ações rápidas + listas recentes (últimos alunos, últimas aulas)

**Base de design (reutilizável nas Etapas 5/6)**
- `public/css/style.css` reescrito: tema claro, tokens (cores/raio/sombra) e componentes:
  `.kpi`, `.alert` (info/warning/danger/ok), `.badge` (status), `.toast`, modal com
  `.modal-head/.modal-body/.modal-foot`, `.form-section`, botões `.mini`, `.tabela-wrap`
- `public/js/ui.js` novo → `toast(msg)` e `ligaFecharModais(modal)`
- Todos os CRUDs atualizados para o padrão: modal com header/fechar/rodapé, botão de salvar com loading (desabilita durante salvar), toast de sucesso, badges de status na tabela, campos em coluna única/agrupados
- Login com card claro + logo

**Nota:** MIGRACAO_ETAPA4.sql continua pendente de aplicar (não bloqueia o dashboard).

---

## 9. Etapa 5 — Financeiro (implementada; migração a aplicar)

**Página nova:** `public/financeiro.html` + `public/js/financeiro.js` (RF23–RF30)

- **RPC `gerar_mensalidades()`** (em `MIGRACAO_ETAPA5.sql`): gera mensalidade por mês para toda matrícula **ativa + mensal**, do mês de `data_inicio` até o mês atual, no valor da turma (`turmas.valor_mensal`) ou da matrícula individual. Guard **admin** dentro da função (RN01); marca `pendente → atrasada` quando `vencimento < CURRENT_DATE`. Índices únicos parciais (`uq_financeiro_mensalidade`, `uq_financeiro_avulsa`) impedem duplicidade.
- **Aula avulsa (RN02):** triggers `AFTER INSERT`/`AFTER DELETE` em `conteudos_ministrados` (SECURITY DEFINER) criam a cobrança `aula_avulsa` no valor da aula (`matriculas.valor_aula`) e a **cancelam** (RN08: nunca apaga financeiro) quando a aula é excluída. Só para matrícula individual **avulsa**.
- **Tela:** menu completo (navbar em todas as páginas), KPIs **A receber no mês / Recebido no mês / Em atraso**, filtros por status e competência (mês), total da lista, botões **Baixar** (data + forma: pix/cartão/dinheiro/boleto) e **Cancelar** por linha, modal **+ Novo lançamento** (ajuste/mensalidade/aula avulsa manual).
- **Restrição:** se o perfil não for admin, a página mostra "Acesso restrito" (RF30); RLS de `financeiro` continua admin-only (já existia na Etapa 2).
- **Menus:** link `Financeiro` ativo em todas as 7 páginas (antes `data-futuro`); `Relatórios` continua bloqueado (Etapa 6).

**Banco — ⚠️ pendente de aplicar:**

- `MIGRACAO_ETAPA5.sql` **NÃO aplicado ainda** → rodar no Supabase > SQL Editor:
  1. índices únicos `uq_financeiro_mensalidade` / `uq_financeiro_avulsa`
  2. função `gerar_mensalidades(date)` + `GRANT EXECUTE ... TO authenticated`
  3. triggers `trig_financeiro_avulsa_insert` / `trig_financeiro_avulsa_delete`

**Bug corrigido nesta sessão:** `popularInstrumentos(sb)` e `popularFormacoes()` em `professores.js`/`turmas.js` haviam sido colocados dentro do bloco de submit por engano; foram movidos para o **carregamento** da página (o `datalist` de instrumentos/formações não aparecia).

**Validação:** todos os `public/js/*.js` passam em `node --check` (v24).

---

## 10. Etapa 6 — Matrícula (recibo) + Carnê 12x/6x/1x + Responsável (implementada; migração a aplicar)

**Decisões do usuário:** (1) carnê gera lançamentos reais + documento; (2) dia de vencimento fixo configurável na matrícula; (3) valor final do curso + escolha de **1, 6 ou 12 parcelas** (parcela = mês); (4) **matrícula gera lançamento próprio pago no ato** (taxa `valor_matricula`, nunca tratada como parcela); (5) menor exige responsável obrigatório p/ documentação; (6) individual (VIP) tem horário fixo e consta como **"Aluno VIP"** nos documentos.

**Banco — `MIGRACAO_ETAPA6.sql`:**
- `tipo_pagamento` += `parcelado`; `tipo_lancamento` += `matricula`
- `matriculas` += `valor_matricula`, `valor_total`, `parcelas (1/6/12)`, `dia_vencimento (1–28, default 5)`, `dia_semana`, `horario`, `matricula_forma_pagamento`
- `alunos` += `responsavel_nome`, `responsavel_cpf`, `responsavel_telefone`, `parentesco`
- Trigger `trig_financeiro_matricula`: ao inserir matrícula com `valor_matricula > 0`, cria lançamento `tipo='matricula'` **pago no ato** (status `paga`, `data_pagamento` = hoje, forma escolhida)
- RPC `gerar_carne(matricula_id)`: gera N parcelas (`tipo='mensalidade'`, descrição "Parcela i/N - curso/VIP"), parcela = `valor_total/N` p/ as N-1 primeiras e última absorve o resto do arredondamento, `competencia` = mês i desde `data_inicio`, `vencimento` = dia fixo do mês; **bloqueia menor sem responsável**; `ON CONFLICT` no índice único (não duplica); admin-only
- `gerar_mensalidades` (recorrente) passa a **ignorar** matrículas `parcelado` (carnê cobre); descrição de individual virou "Aluno VIP"
- Índices únicos parciais recriados com `IF NOT EXISTS` (idempotente, não depende de ETAPA5)

**UI:**
- `alunos.html/js`: bloco "Responsável (menor)" visível quando idade < 18; obrigatório (nome + CPF + telefone) no salvar
- `matriculas.html/js`: taxa de matrícula + forma (paga no ato), valor do curso + radio 1x/6x/12x, dia do vencimento, horário fixo p/ individual; botões **Recibo** e **Carnê** por linha; ao criar matrícula parcelada gera o carnê automaticamente (RPC)
- `public/carne.html` + `public/js/carne.js` + `public/css/imprimir.css`: página de impressão A4 (`?matricula=ID&tipo=recibo|carne`) com **2 vias** ("1ª VIA — ALUNO" / "2ª VIA — ESCOLA") e grade de parcelas; carnê exclusivo de admin (RF30), recibo para todo logado
- `financeiro.js`: badge "menor — resp. X", botão "Carnê" por lançamento (imprime do vínculo)

**Banco — ⚠️ pendente de aplicar (depende de ETAPA5):**
- Executar `MIGRACAO_ETAPA5.sql` e depois `MIGRACAO_ETAPA6.sql` no Supabase > SQL Editor. Ordem: **ETAPA5 primeiro** (mesmas funções/índices são redefinidas idempotentemente na ETAPA6, mas o fluxo previsto é ETAPA5 → ETAPA6).

---

## 11. Etapa 7 — Relatórios (gráficos) (implementada)

Nova página **Relatórios** (`public/relatorios.html` + `public/js/relatorios.js`), consumindo as views `vw_*` do SCHEMA.sql, com gráficos **SVG puros sem dependência** (`public/js/graficos.js`): linha (com área) e barras agrupadas, grid e eixos montados à mão.

- **Desempenho da turma** — evolução média % por aula (`vw_desempenho_turma`), seletor de turma ativa
- **Desempenho por aluno** — avaliações por data (`vw_desempenho_aluno`), seletor de aluno ativo
- **Financeiro por competência** — a receber × recebido por mês (`vw_financeiro_resumo`), **admin only** (seção oculta p/ professor)
- Link `Relatórios` desbloqueado (era `data-futuro`) em **todas as páginas**

**CSS:** `.grafico-card`, `.graf-head`, `.graf-sel`, `.grafico` (svg), `.graf-vazio`, `.graf-legend`.

**Seed de teste (auxiliar):** `SEED_TESTE.sql` — 10 professores, 10 turmas (1 por instrumento), 30 alunos (5 menores com responsável), 30 matrículas (turma/individual; parcelado 1/6/12x, mensal, avulsa) + parcelas do carnê injetadas direto em `financeiro`. Idempotente. Inclui relaxamento da constraint `matriculas_check2` (turma agora aceita `parcelado`, não só `mensal`) — **aplicado** pelo usuário; seed validado com sucesso.

---

## 12. Etapa 8 — Exportação CSV (RF35) e Etapa 9 — Troca de senha (RF04) (implementadas)

**Etapa 8 — CSV:**
- `public/js/csv.js` → `baixarCsv(nome, colunas, linhas)` (delimitador `;`, BOM UTF-8 para abrir certo no Excel pt-BR) + `exportarTabela(tabela, nome)`; auto-injeta o botão **"↓ Exportar CSV"** acima de toda `table[data-export]`
- Com `data-export` nas tabelas de **Financeiro, Alunos, Matrículas e Turmas** (exporta a lista conforme os filtros atuais; coluna "Ações" é ignorada)
- **Relatórios**: botões de exportar por gráfico (`desempenho_turma_*`, `desempenho_aluno_*`, `financeiro_por_competencia`), com os dados plotados

**Etapa 9 — Troca de senha (RF04):**
- `public/js/senha.js` injeta o botão **"Senha"** no topbar (`public/js/auth.js` não é alterado) e um `<dialog>` de troca usando `sb.auth.updateUser({password})`; valida min 6 + confirmação; mantém a sessão
- Adicionado como `<script type="module" src="/js/senha.js">` nas 9 páginas logadas

**Validação:** `node --check` em `csv.js`, `senha.js`, `relatorios.js` (v24) — OK.

---

## 13. Estado atual do projeto

Repositório: https://github.com/AdaoElias/escola-de-musica
Site: https://escola-demusica.netlify.app
Banco: Supabase (tabelas do SCHEMA.sql + migrations ETAPA2/REDESIGN/FIX_RLS/ENDERECO/CPF_NASCIMENTO/ETAPA5/ETAPA6 aplicadas; ETAPA4 pendente)

```
public/            → index(login), app(painel), professores, alunos, turmas, matriculas, grade, aulas, financeiro, relatorios, carne (impressão)
public/js/         → supabase.js, auth.js, ui.js, csv.js (export), senha.js (troca senha), app.js, professores.js, alunos.js, turmas.js, matriculas.js, grade.js, aulas.js, financeiro.js, relatorios.js, graficos.js (svg), carne.js, instrumentos.js
public/css/style.css (design system claro) + imprimir.css (recibo/carnê A4)
functions/         → hello.js, health.js, client-config.js
netlify.toml, .env.example, .env.local (não versionado)
REQUISITOS.md, SCHEMA.sql (baseline ETAPA6), MIGRACAO_ETAPA2/4/5/6.sql, MIGRACAO_ENDERECO.sql, MIGRACAO_CPF_NASCIMENTO.sql, MIGRACAO_FIX_RLS.sql, SEED_TESTE.sql
```

**Migrações ETAPA5 e ETAPA6 já aplicadas** no Supabase. **ETAPA4 ainda pendente.**

**FIX (a aplicar no Supabase):** `MIGRACAO_FIX_RLS.sql` — funções `usuario_atual/administrador_atual/professor_atual` agora são `SECURITY DEFINER`. Sem isso, todo CRUD/logado estoura "stack depth limit exceeded" (recursão de RLS: função lê usuarios/professores → política da própria tabela chama a função de novo).

**Migração `MIGRACAO_ENDERECO.sql`:** adiciona `endereco, bairro, cidade, cep` em `professores` e `alunos`. Forms com busca de CEP via **ViaCEP** (helper `buscarCep` em `ui.js`).

**Conta de teste ativa:** `teste@escola.com` (admin). Sugestão: trocar pela conta definitiva.

---

## 14. Próximos passos

- ✅ **Etapa 0–7** concluídas (requisitos, ambiente, RLS/login, cadastros, grade/aulas, financeiro, carnê/recibo, relatórios)
- ✅ **Etapa 8** Exportação CSV (financeiro, alunos, matrículas, turmas, relatórios)
- ✅ **Etapa 9** Troca de senha pelo próprio usuário
- ✅ Fim do roadmap original (`REQUISITOS.md` RF01–RF35 cobertos)

**Pendências anotadas:**
- ✅ **`MIGRACAO_PENDENTE.sql` aplicada** (22/09/2026): FIX_RLS (funções SECURITY DEFINER) + views `vw_progresso_turma/vw_progresso_aluno` — nenhuma pendência de banco restante
- Excluir/ajustar conta `teste@escola.com` e criar e-mail definitivo de admin
- Avaliar liberação: professor acessa só com conta vinculada (`professores.usuario_id`)
- Opcional: recuperação de senha via e-mail (Supabase Auth recovery) — hoje a troca é feita logado (Etapa 9)
- Opcional: seed não insere `conteudos_ministrados`/`desempenhos` (gráficos de desempenho ficam vazios até lançar aulas de verdade)