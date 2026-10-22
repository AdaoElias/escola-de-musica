# Registro da Sessão — Escola de Música

> Data: 21/09/2026 (atualizado 21/10/2026) · Continuidade prevista para a próxima sessão.

Este documento registra tudo o que foi pedido, decidido e implementado nesta sessão, além dos problemas resolvidos, para retomada sem perda de contexto.

> **Como ler:** as seções **1–13** são o registro cronológico das etapas (o estado citado nelas
> era o de cada momento). O **estado atual** está na **§14** (estrutura do projeto) e o quadro de
> estado do banco na **§14** e em [`historico/README.md`](historico/README.md).
> As correções técnicas estão na **§15** (consolidação do banco), **§17** (itens #4, #5, #6, #11 e
> #15), **§18** (itens #2, #3, #7, #8, #9, #10, #12, #13 e #14) e **§19** (pacote de instalação
> `INSTALAR_SUPABASE/`).

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

**Banco:** `MIGRACAO_ETAPA4.sql` → ajustes **NÃO aplicados ainda** *(registro de 22/09/2026 — já foram aplicados: as mesmas views vieram no `MIGRACAO_PENDENTE.sql`; ver §14 e `historico/README.md`)*:
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

**Nota:** MIGRACAO_ETAPA4.sql continua pendente de aplicar (não bloqueia o dashboard). *(→ pendência resolvida: as views existem no Supabase; ver §14)*

---

## 9. Etapa 5 — Financeiro (implementada; migração a aplicar)

**Página nova:** `public/financeiro.html` + `public/js/financeiro.js` (RF23–RF30)

- **RPC `gerar_mensalidades()`** (em `MIGRACAO_ETAPA5.sql`): gera mensalidade por mês para toda matrícula **ativa + mensal**, do mês de `data_inicio` até o mês atual, no valor da turma (`turmas.valor_mensal`) ou da matrícula individual. Guard **admin** dentro da função (RN01); marca `pendente → atrasada` quando `vencimento < CURRENT_DATE`. Índices únicos parciais (`uq_financeiro_mensalidade`, `uq_financeiro_avulsa`) impedem duplicidade.
- **Aula avulsa (RN02):** triggers `AFTER INSERT`/`AFTER DELETE` em `conteudos_ministrados` (SECURITY DEFINER) criam a cobrança `aula_avulsa` no valor da aula (`matriculas.valor_aula`) e a **cancelam** (RN08: nunca apaga financeiro) quando a aula é excluída. Só para matrícula individual **avulsa**.
- **Tela:** menu completo (navbar em todas as páginas), KPIs **A receber no mês / Recebido no mês / Em atraso**, filtros por status e competência (mês), total da lista, botões **Baixar** (data + forma: pix/cartão/dinheiro/boleto) e **Cancelar** por linha, modal **+ Novo lançamento** (ajuste/mensalidade/aula avulsa manual).
- **Restrição:** se o perfil não for admin, a página mostra "Acesso restrito" (RF30); RLS de `financeiro` continua admin-only (já existia na Etapa 2).
- **Menus:** link `Financeiro` ativo em todas as 7 páginas (antes `data-futuro`); `Relatórios` continua bloqueado (Etapa 6).

**Banco — ⚠️ pendente de aplicar:** *(registro de 22/09/2026 — já aplicado; ver §14 e `historico/README.md`)*

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

**Banco — ⚠️ pendente de aplicar (depende de ETAPA5):** *(registro de 22/09/2026 — já aplicado; ver §14)*
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

## 13. Acesso do professor (RF06) e recuperação de senha (RF04) — implementadas

Resolve as duas pendências anotadas ao final do roadmap.

**Pendência 2 — vincular professor a uma conta de acesso (RF06):**
- `functions/criar-acesso.js` (nova): recebe `professor_id` + `email` + `acao`. Valida que o chamador é **admin** (confere o JWT via `auth.getUser` e o perfil em `usuarios`) e, usando a **service role**, cria a conta no Supabase Auth (`auth.admin.createUser`, e-mail confirmado) ou localiza uma conta existente (`acao='vincular'`). Em seguida insere/atualiza `usuarios` (`perfil='professor'`) e grava `professores.usuario_id`. Usa `SUPABASE_SERVICE_ROLE_KEY` (nunca exposta ao navegador).
- `public/professores.html`: coluna **Acesso** na tabela e bloco "Acesso ao sistema" no modal.
- `public/js/professores.js`: `renderAcesso()` exibe "Vinculado/Sem acesso" e, quando aplicável, o checkbox "Criar acesso" + senha temporária; no submit, chama `/api/criar-acesso` com `Authorization: Bearer <token>` da sessão. O insert/update do professor passou a usar `.select('id').single()` para obter o id e vincular na sequência.
- `.env.example`: nova variável `SUPABASE_SERVICE_ROLE_KEY`.

**Pendência 3 — recuperação de senha por e-mail (RF04):**
- `public/js/auth.js`: `recuperarSenha(email)` via `sb.auth.resetPasswordForEmail(email, { redirectTo })`.
- `public/index.html`: link "Esqueci minha senha" (usa o e-mail já digitado).
- `public/redefinir.html` (nova): capta a sessão de recovery do link do e-mail e chama `sb.auth.updateUser({ password })`; trata link inválido/expirado.

**Ações externas necessárias (não-código):**
1. Definir `SUPABASE_SERVICE_ROLE_KEY` no Netlify (Site configuration → Environment variables) e no `.env.local` local.
2. Supabase → Authentication → URL Configuration: Site URL + Redirect URLs incluindo `/redefinir.html` (produção e local).

**Validação:** `node --check` OK em `functions/criar-acesso.js`, `public/js/professores.js` e `public/js/auth.js`.

---

## 14. Estado atual do projeto

Repositório: https://github.com/AdaoElias/escola-de-musica
Site: https://escola-demusica.netlify.app
Banco: Supabase — **fonte única: `INSTALAR.sql`**. Quadro de estado de cada arquivo antigo em
[`historico/README.md`](historico/README.md). Pacote de aplicação colado por blocos em
[`INSTALAR_SUPABASE/`](INSTALAR_SUPABASE/README.md).

```
public/            → index(login), redefinir(senha), app(painel), professores, alunos, turmas, matriculas, grade, aulas, financeiro, relatorios, carne (impressão)
public/js/         → supabase.js, auth.js, ui.js, csv.js (export), senha.js (troca senha), app.js, professores.js, alunos.js, turmas.js, matriculas.js, grade.js, aulas.js, financeiro.js, relatorios.js, graficos.js (svg), carne.js, instrumentos.js
public/js/vendor/  → cliente Supabase vendorizado (8 bundles ESM; sem CDN no runtime)
public/css/style.css (design system claro) + imprimir.css (recibo/carnê A4)
functions/         → hello.js, health.js, client-config.js, criar-acesso.js (gestão de acesso do professor)
netlify.toml, .env.example (inclui SUPABASE_SERVICE_ROLE_KEY), .env.local (não versionado)
REQUISITOS.md, INSTALAR.sql (instalação única do banco), SEED_TESTE.sql (dados de teste)
INSTALAR_SUPABASE/ → o mesmo INSTALAR.sql em 11 blocos prontos para colar + guia de aplicação
historico/         → SCHEMA.sql + MIGRACAO_*.sql (memória do processo; NÃO usar para instalar)
testes/            → suíte de regressão do banco (4 arquivos de asserção) + run.ps1 / run.sh
scripts/           → backup.ps1, backup.sh, restaurar.ps1 (RNF04)
.github/workflows/ → testes.yml (CI: PostgreSQL 16 + node --check)
```

**Instalação do banco:** `INSTALAR.sql` é a **fonte única** (idempotente, base nova ou existente). Os
arquivos em `historico/` são memória do processo — não usar para instalar.

**Estado do banco no Supabase:** schema consolidado e **sem pendências de estrutura** — o
`INSTALAR.sql` novo **já foi aplicado** (21/10/2026, ver §20). As views de progresso
(`vw_progresso_turma`/`vw_progresso_aluno`) já existem (criadas pelo `MIGRACAO_PENDENTE.sql`,
idêntico ao ETAPA4). Falta apenas rodar o `09_grants.sql` (ver §20.1) e conferir a contagem de
registros (ver §20.2).

**Testes:** suíte de regressão versionada em `testes/` (rodar `.\testes\run.ps1` ou `./testes/run.sh`);
CI em `.github/workflows/testes.yml` roda a suíte e o `node --check` em cada push/PR.

**Backup:** `scripts/backup.ps1` / `backup.sh` geram o dump; `scripts/restaurar.ps1` valida a
restauração. O dump **não** é versionado (contém dados pessoais — RNF06).

**Colunas de endereço:** `endereco, bairro, cidade, cep` em `professores`/`alunos`. Forms com busca de
CEP via **ViaCEP** (helper `buscarCep` em `ui.js`).

**Conta admin:** `adaoelias@gmail.com` (admin) — renomeada a partir de `teste@escola.com`; o vínculo se mantém por `auth_uid`.

---

## 15. Consolidação do banco — `INSTALAR.sql` (fonte única)

Revisão técnica do projeto levantou que **`SCHEMA.sql` não era instalável sozinho**: as RPCs de
financeiro (`gerar_mensalidades`, `gerar_carne`) e os triggers (aula avulsa, taxa de matrícula)
só existiam em `MIGRACAO_ETAPA5.sql` / `MIGRACAO_ETAPA6.sql`. Um banco novo instalado só com o
`SCHEMA.sql` ficaria **sem mensalidade automática e sem carnê**.

Além disso, a cadeia antiga de migrations **não é re-executável**: `MIGRACAO_ETAPA2.sql:8` falha
com `relação "usuarios_auth_uid_key" já existe` quando rodada sobre o `SCHEMA.sql` atual
(a constraint é criada duas vezes, com nomes diferentes).

**Feito:**

- **`INSTALAR.sql` (novo)** — script único, completo e idempotente. Contém: 8 enums · 9 tabelas ·
  colunas faltantes (ADD COLUMN condicional) · constraints com **nome determinístico** ·
  normalização dos constraints antigos (remove duplicados) · 13 índices · funções de RLS
  `SECURITY DEFINER` · 37 políticas · RPCs e triggers de financeiro · 6 views · grants ·
  checagem final no próprio script.
- **`SEED_TESTE.sql`** — deixou de criar `matriculas_check2` (constraint duplicado); passa a
  garantir os constraints com nome determinístico.
- **`REQUISITOS.md`** — nova seção §9.1 (instalação) e §10 passo 2 corrigido.
- **`public/js/matriculas.js`** — validação de matrícula duplicada com mensagem amigável
  (turma: mesmo aluno na mesma turma · individual: mesmo aluno + mesmo professor).

**Regra de negócio definida (item #4):** matrícula individual é única por **aluno + professor**
(`uq_matriculas_individual`, índice único parcial `WHERE turma_id IS NULL`). O mesmo aluno pode
ter aula individual com professores diferentes, mas não repetir com o mesmo. O `UNIQUE`
original `UNIQUE (aluno_id, turma_id, tipo)` **não** protegia esse caso: em PostgreSQL
`NULL ≠ NULL` dentro de índice único, então matrículas individuais duplicadas passavam.

**Validação (PostgreSQL 16 local, banco de verdade):**

| Cenário | Resultado |
|---|---|
| Base nova → `INSTALAR.sql` | ok — 9 tabelas, 6 views, 37 políticas, 9 funções, 3 triggers |
| Rodar `INSTALAR.sql` 2x | ok — idempotente, sem erro nem duplicata |
| Base legada (SCHEMA + migrations) → `INSTALAR.sql` | ok — converge para o mesmo estado |
| `INSTALLAR` → `SEED` → `INSTALLAR` → `SEED` | ok — seed idempotente, sem constraint duplicado |
| Matrícula de turma duplicada | bloqueada (`uq_matriculas_aluno_turma_tipo`) |
| Matrícula individual duplicada | bloqueada (`uq_matriculas_individual`) |
| Matrícula individual com outro professor | permitida |
| Soma das parcelas do carnê = `valor_total` | ok — 0 divergências |

**Ação manual necessária:** aplicar `INSTALAR.sql` no Supabase > SQL Editor (base nova) ou rodar
apenas o Bloco 0 (enums) e depois o restante (base atual). O script normaliza o schema sem
apagar dados.

**Arquivos que viraram histórico** (movidos para `historico/`): `SCHEMA.sql`,
`MIGRACAO_ETAPA2/4/5/6.sql`, `MIGRACAO_ENDERECO.sql`, `MIGRACAO_CPF_NASCIMENTO.sql`,
`MIGRACAO_FIX_RLS.sql`, `MIGRACAO_PENDENTE.sql` — não use mais para instalar; use `INSTALAR.sql`.
O quadro de estado de cada arquivo está em [`historico/README.md`](historico/README.md).

---

## 16. Próximos passos

- ✅ **Etapa 0–7** concluídas (requisitos, ambiente, RLS/login, cadastros, grade/aulas, financeiro, carnê/recibo, relatórios)
- ✅ **Etapa 8** Exportação CSV (financeiro, alunos, matrículas, turmas, relatórios)
- ✅ **Etapa 9** Troca de senha pelo próprio usuário
- ✅ **Etapa 10** Acesso do professor (RF06) + recuperação de senha por e-mail (RF04)
- ✅ Fim do roadmap original (`REQUISITOS.md` RF01–RF35 cobertos)
- ✅ **Revisão técnica de consistência** (21/10/2026): 14 itens + 1 achado novo (#15) corrigidos — ver §17, §18 e §19
- ✅ **`INSTALAR.sql` aplicado no Supabase** (21/10/2026) — verificação por sonda PostgREST: `cpf_valido`, `alunos.cpf`, `professores.cpf` e `matriculas.dia_vencimento` presentes, controles negatively (ver §20)

**Pendências anotadas:**
- 🔴 **Rodar só o `09_grants.sql` no Supabase** — revoga o `EXECUTE` padrão que o Postgres dá ao
  papel `PUBLIC` (o papel `anon` conseguia chamar as RPCs de financeiro; hoje inofensivo porque as
  RPCs exigem `administrador_atual()`, mas a permissão é ampla demais). Idempotente, 1 s. Ver §20.1
- 🔴 **Conferir se o banco tem dados** — o papel `anon` não lê as tabelas (RLS); rodar a query de
  contagem no SQL Editor (ou fornecer a senha do banco para um `psql` somente-leitura). Ver §20.2
- ✅ **`MIGRACAO_PENDENTE.sql` aplicada** (22/09/2026): FIX_RLS (funções SECURITY DEFINER) + views `vw_progresso_turma/vw_progresso_aluno` — nenhuma pendência de banco restante
- ✅ **Acesso do professor** (RF06): criar/vincular conta pela tela de Professores (`criar-acesso.js` + `professores.js`) — exige `SUPABASE_SERVICE_ROLE_KEY` no Netlify/.env.local
- ✅ **Recuperação de senha** (RF04): link no login + `redefinir.html` — exige `/redefinir.html` nas Redirect URLs do Supabase
- ✅ Conta admin definida: `adaoelias@gmail.com` (renomeada de `teste@escola.com`; trocar a senha temporária no primeiro acesso)
- Opcional: seed não insere `conteudos_ministrados`/`desempenhos` (gráficos de desempenho ficam vazios até lançar aulas de verdade)
- Opcional: realinhar o vencimento das mensalidades já geradas (SQL em `INSTALAR_SUPABASE/README.md`)
- Decisões de produto em aberto (não bloqueiam): registro de consentimento LGPD (RNF06), observabilidade
  (Sentry/Logtail), manual de uso para o admin, versão do runtime Node fixada no `netlify.toml`
- Fora do escopo do código: commit e push das mudanças (a árvore de trabalho está suja, nada foi commitado)

---

## 17. Correções de consistência — itens #4, #5 e #6

Revisão técnica do banco (21/10/2026) levantou 14 inconsistências. As três primeiras
foram corrigidas e validadas no PostgreSQL 16 local — as demais estão na **§18**
(itens #2, #3, #7, #8, #9, #10, #12, #13 e #14) e o pacote de instalação na **§19**.

### #4 — Matrícula individual duplicada (resolvido)

- **Banco:** `uq_matriculas_individual` — índice único parcial em `matriculas (aluno_id, professor_id)`
  `WHERE turma_id IS NULL`. O `UNIQUE (aluno_id, turma_id, tipo)` original **não** protegia esse
  caso: em PostgreSQL `NULL ≠ NULL` dentro de índice único, então matrículas individuais duplicadas
  passavam. Detalhe em `REQUISITOS.md` RN12.
- **Front:** `public/js/matriculas.js` — `validarDuplicidade()` consulta `matriculas` antes de
  salvar (turma: mesmo aluno na mesma turma · individual: mesmo aluno + mesmo professor) e traduz
  o erro `23505` do Postgres em mensagem amigável.

### #5 — Desconto (RF29) era impossível no banco (resolvido)

- **Antes:** `financeiro.valor` tinha `CHECK (valor >= 0)` e o cancelamento usava
  `status = 'cancelada'` → **não existia representação de desconto/crédito**.
- **Decisão:** desconto é lançamento do tipo `ajuste` com **valor negativo**; `mensalidade` e
  `aula_avulsa` continuam obrigatoriamente ≥ 0 (protege o cálculo de "a receber").
- **Banco:** `financeiro_check_valor` → `CHECK (valor >= 0 OR tipo = 'ajuste')`.
  `vw_inadimplentes` passou a ignorar `ajuste` (crédito não é inadimplência) e
  `gerar_mensalidades` não marca ajuste negativo como `atrasada`.
- **Front:** `public/js/financeiro.html` + `public/js/financeiro.js` — o campo valor aceita
  negativo só em "Ajuste manual" (o `min="0"` sumia ao trocar o tipo), com dica na tela e
  validação no envio.
- **Testado:** ajuste −50,00 aceito · mensalidade −50,00 **rejeitada** · aula avulsa −10,00
  **rejeitada** · ajuste +25,00 aceito · `a_receber` da view confere com a soma manual (2.310,00).

### #6 — CPF sem unicidade e sem validação de dígitos (resolvido)

- **Banco:** função `public.cpf_valido(text)` (dígitos verificadores, IMMUTABLE) + CHECKs
  `alunos_cpf_valido`, `professores_cpf_valido`, `alunos_responsavel_cpf_valido` +
  índices únicos `uq_alunos_cpf` / `uq_professores_cpf` (comparam **só os dígitos**, então
  `123.456.789-00` e `12345678900` contam como o mesmo CPF).
  `responsavel_cpf` **não** é único — o mesmo responsável pode ter vários filhos.
- **Sem travar a instalação:** os CHECKs entram como `NOT VALID` e os índices de CPF só são
  criados se não houver duplicidade. Em base legada inconsistente o `INSTALAR.sql` **avisa** e
  continua (exit 0), indicando a query de correção — ver `REQUISITOS.md` §9.1.
- **Front:** `public/js/ui.js` ganhou `cpfValido()` e `erroAmigo()` (traduz `23505`/`23514`/
  `23503` do Postgres); `alunos.js` e `professores.js` validam os dígitos antes de salvar e
  traduzem CPF duplicado em "Já existe um cadastro com este CPF".
- **Seed:** `SEED_TESTE.sql` passou a gerar **CPFs com dígitos válidos** (função auxiliar
  `public.seed_cpf`, removida no final do seed) — os CPFs de teste antes eram inválidos.

| Cenário | Resultado |
|---|---|
| `INSTALAR` → `SEED` → `INSTALAR` → `SEED` | ok — 30 alunos, 10 profs, 30 matrículas, 132 lançamentos, 2 índices de CPF, 3 CHECKs validados |
| CPF duplicado (mesma máscara / máscara diferente) | bloqueado (`uq_alunos_cpf`) |
| CPF com dígitos inválidos | bloqueado (`alunos_cpf_valido`) |
| `responsavel_cpf` repetido (mesmo responsável, 2 filhos) | permitido |
| Base legada com CPF duplicado + inválido | `INSTALAR.sql` avisa e conclui sem erro (índices de CPF não criados) |

### #11 — `gerar_mensalidades` ignorava `dia_vencimento` (resolvido)

- **Antes:** o vencimento da mensalidade era sempre o **último dia do mês** (`(m + 1 mês) - 1`),
  ignorando o `dia_vencimento` contratado na matrícula — enquanto o carnê usava o dia correto.
  Aluno com vencimento no dia 10 era cobrado só no dia 30/31.
- **Depois:** `gerar_mensalidades` usa a mesma regra do carnê — `competência + (dia_vencimento - 1)` dias.
  Mensal e parcelado passam a vencer no mesmo dia.

### #15 (novo) — RPC `gerar_carne` estava quebrada (resolvido)

Bug **crítico** encontrado ao validar o item #11: o carnê nunca foi gerado pela interface.

- **Causa:** `gerar_carne(matricula_id BIGINT)` usava `WHERE id = matricula_id` — o parâmetro da
  RPC tinha o **mesmo nome da coluna**, e o PL/pgSQL acusava
  `referência à coluna "matricula_id" é ambígua`. O mesmo conflito acontecia no
  `ON CONFLICT (matricula_id, ...)`. Herdado de `MIGRACAO_ETAPA6.sql:149` (nunca detectado porque
  o `SEED_TESTE.sql` insere as parcelas direto, sem passar pela RPC).
- **Correção:** `WHERE id = gerar_carne.matricula_id` (referência qualificada) e
  `ON CONFLICT DO NOTHING` sem alvo de colunas.
- **Efeito:** criar matrícula parcelada pela tela volta a gerar o carnê (o front já chamava a RPC
  e mostrava o erro em toast).

### Correção pontual para base já em produção (opcional)

Mensalidades **já geradas** antes da correção mantêm o vencimento antigo. Para alinhar apenas as
cobranças em aberto (sem tocar nas pagas):

```sql
UPDATE public.financeiro f
   SET vencimento = date_trunc('month', f.competencia)::date
                    + (mt.dia_vencimento - 1) * interval '1 day'
  FROM public.matriculas mt
 WHERE f.matricula_id = mt.id
   AND f.tipo = 'mensalidade'
   AND f.status IN ('pendente', 'atrasada')
   AND f.vencimento <> date_trunc('month', f.competencia)::date
                            + (mt.dia_vencimento - 1) * interval '1 day';
```

### Validação completa (PostgreSQL 16 local, suíte `test_final.ps1`)

| Cenário | Resultado |
|---|---|
| `INSTALAR` → `SEED` → `INSTALAR` → `SEED` | ok — 9 tabelas, 6 views, 37 políticas, 10 funções, 3 triggers, 7 índices únicos, 132 lançamentos |
| Desconto: ajuste −50,00 / mensalidade −50,00 / aula avulsa −50,00 | ok · bloqueada · bloqueada |
| Ajuste negativo não vira inadimplência | ok |
| CPF: duplicado (2 formatos), dígitos inválidos, `responsavel_cpf` repetido | bloqueado · bloqueado · permitido |
| Base legada → `INSTALAR.sql` | ok — converge (9 tabelas, 37 políticas) |
| Base legada com CPF duplicado/inválido | `INSTALAR.sql` avisa e conclui sem erro |
| `gerar_mensalidades` respeita `dia_vencimento` | ok — vence no dia 10 de cada competência |
| `gerar_carne` (RPC) | ok — 6 parcelas, soma = `valor_total`, idempotente, arredondamento absorvido na última |

---

## 18. Correções de consistência (2ª rodada) — itens #2, #3, #7, #8, #9, #10, #12, #13 e #14

### #2 / #3 / #14 — Higiene dos arquivos SQL (resolvido)

- Os 9 arquivos antigos foram movidos para `historico/` (via `git mv`, histórico preservado) e
  `historico/README.md` passou a ser o **quadro de estado único** (arquivo → o que fazia → situação
  → substituído por). Fica registrado ali que `MIGRACAO_ETAPA4.sql` e `MIGRACAO_PENDENTE.sql`
  criam **views idênticas** (`vw_progresso_turma` / `vw_progresso_aluno`) — o ETAPA4 é redundante.
- **`MIGRACAO_REDESIGN.sql` não existe** no repositório, embora fosse citado no registro: a
  referência foi removida do §14 (o texto antigo afirmava "ETAPA4 pendente", o que era falso).
- `public/js/aulas.js:140` mandava o usuário "executar MIGRACAO_ETAPA4.sql no Supabase" → agora
  aponta para `INSTALAR.sql`.
- O §14 do registro passou a descrever o estado real (banco consolidado, sem pendências), com nota
  no topo do arquivo avisando que §1–13 são o registro cronológico.

### #7 — Cliente Supabase duplicado / CDN no runtime (resolvido)

- O front importava o cliente de `https://esm.sh/@supabase/supabase-js@2.45.0` (CDN de terceiros)
  enquanto o `package.json` usava `^2.45.0` (divergência silenciosa).
- O pacote e toda a árvore de dependências foram **vendorizados** em `public/js/vendor/` (8 bundles
  ESM, mesma versão do npm, imports reescritos para caminhos locais) — o runtime não depende mais
  de CDN. Testado em Node: `createClient()` + `from`/`rpc`/`auth`/`channel` funcionam.
- `package.json` passou a fixar `"@supabase/supabase-js": "2.45.0"` (versão única dos dois lados).
- `public/js/vendor/README.md` documenta a procedência, as versões e como atualizar.

### #8 — `usuarios.senha_hash` (resolvido como legado)

- A coluna é mantida (não há dado de senha real nela), mas passa a ser declarada como **legada**:
  comentário no `INSTALAR.sql` e aviso em `REQUISITOS.md` §8. Removê-la é irreversível e não
  traria ganho funcional — a senha é gerenciada pelo Supabase Auth.

### #9 — `grade_conteudos.tempo_estimado` (resolvido)

- A UI grava **minutos** (`PT30M` → INTERVAL) e a leitura converte de volta — o medo da revisão
  era que "7" pudesse virar 7 dias. Agora há uma constraint que amarra o intervalo:
  `grade_conteudos_tempo_estimado_check` (`0 < tempo_estimado <= 12 horas`), criada `NOT VALID`
  e validada quando não há registro legado fora do padrão.

### #10 — Professor inativado com turmas ativas (resolvido — RN14)

- **Banco:** dois triggers novos — `trig_professores_bloqueia_inativacao` (não permite inativar
  professor com turma ativa) e `trig_turmas_exige_professor_ativo` (não permite ativar turma
  cujo professor esteja inativo). Erro em português claro (`P0001`).
- **Front:** `professores.js` consulta as turmas ativas antes de inativar (bloqueia com
  explicação) e avisa quantas matrículas ativas continuam vinculadas; `turmas.js` marca o
  professor inativo com badge e impede salvar turma ativa com professor inativo; `app.js`
  (painel) alerta "Turma sem professor ativo"; `ui.js` traduz o erro do banco.

### #12 — Testes automatizados e CI (resolvido)

- A suíte que rodava fora do repositório foi **versionada** em `testes/`:
  `sql/01_estrutura.sql`, `sql/02_regras_cpf_desconto.sql`, `sql/03_vencimento_carne.sql`,
  `sql/04_professor_ativo.sql`, com `run.ps1` (Windows) e `run.sh` (Linux).
- Cenários: base nova (INSTALAR → SEED → INSTALAR → SEED) e base legada (`historico/*.sql` →
  INSTALAR converge). Os bancos temporários são apagados no final.
- As asserções de unicidade são **semânticas** (não por nome de índice): em base legada o índice
  pode ter outro nome, mas a regra precisa existir.
- **CI:** `.github/workflows/testes.yml` — PostgreSQL 16 como serviço, roda a suíte em cada
  push/PR e faz `node --check` de `public/js/*.js` e `functions/*.js`.

### #13 — RNF04 backup sem evidência (resolvido)

- `scripts/backup.ps1` e `scripts/backup.sh` (`pg_dump` com rotação, mantém 10 dumps) e
  `scripts/restaurar.ps1` (restaura e confere tabelas/alunos), com `scripts/README.md`.
- **Decisão:** o dump **não** é versionado no Git (contém CPF, nascimento, endereço e responsável
  de menores — RNF06/LGPD). O repositório guarda o *procedimento*; o dump fica em bucket privado.
  `.gitignore` bloqueia `backups/` e `*.sql.gz`.

### Estado final do banco (após esta rodada)

9 tabelas · 6 views · 37 políticas · 12 funções · 5 triggers · 7 índices únicos · seed com
10 professores, 10 turmas, 30 alunos, 30 matrículas e 132 lançamentos.

### Validação (suíte versionada `testes/run.ps1`, PostgreSQL 16 local)

| Cenário | Resultado |
|---|---|
| Base nova: INSTALAR → SEED → INSTALAR → SEED | ok - idempotente |
| `01_estrutura` (base nova e legada) | ok |
| `02_regras_cpf_desconto` (#5, #6) | ok |
| `03_vencimento_carne` (#11, #15) | ok |
| `04_professor_ativo` (#10 / RN14) | ok |
| Base legada → INSTALAR | ok - converge |
| `node --check` em `public/js/*.js` | ok - 17 arquivos |

### Itens ainda abertos na revisão técnica

Nenhum dos 14 itens originais fica pendente de correção. Restam apenas **decisões de produto**
não bloqueantes (registro de consentimento LGPD, observabilidade, manual de uso) e a aplicação
manual do `INSTALAR.sql` no Supabase.

---

## 19. Pacote de instalação para o Supabase (`INSTALAR_SUPABASE/`)

O `INSTALAR.sql` foi dividido em **11 blocos** prontos para colar no SQL Editor do Supabase, com
guia passo a passo em `INSTALAR_SUPABASE/README.md`:

| Arquivo | Conteúdo |
|---|---|
| `00_enums.sql` | Enums (e os valores `'parcelado'` / `'matricula'`) |
| `01_tabelas.sql` | 9 tabelas + FKs |
| `02_colunas.sql` | Colunas adicionadas depois (`cpf`, `nascimento`, `endereco`…) |
| `03_constraints.sql` | Constraints nomeadas + `public.cpf_valido()` |
| `04_indices.sql` | Índices (inclui `uq_matriculas_individual` e os de CPF) |
| `05_funcoes_rls.sql` | Funções de RLS `SECURITY DEFINER` + `health_check` |
| `06_rls_politicas.sql` | RLS + 37 políticas |
| `07_regras_negocio.sql` | RPCs + triggers de financeiro + RN14 |
| `08_views.sql` | 6 views de relatório |
| `09_grants.sql` | Grants para `anon`/`authenticated`/`service_role` |
| `10_checagem_final.sql` | Consulta de conferência |

### Validação

- Cada bloco roda ** isoladamente** sem erro, em base nova e em base legada (PostgreSQL 16 local).
- O `INSTALAR.sql` **inteiro** também roda em **transação única** (`psql -1`, igual ao SQL Editor
  do Supabase) nos dois cenários — ou seja, colar tudo de uma vez funciona. O único risco é
  `unsafe use of new value` de enum, que só aparece se o Bloco 0 e o Bloco 1 forem colados juntos
  numa base legada sem os valores — nesse caso, use a ordem por blocos.
- Resultado final idêntico nos dois caminhos: **9 tabelas · 6 views · 37 políticas · 12 funções ·
  5 triggers**.

O guia também traz: backup antes de aplicar, os **avisos esperados** (CPF duplicado/inválido
legado) com as queries de correção, o SQL opcional de realinhamento de vencimentos e uma lista de
**6 testes rápidos na interface** depois do deploy.


---

## 20. Verificação da instalação no Supabase + correção de privilégio (21/10/2026)

O `INSTALAR.sql` foi aplicado no Supabase (projeto `tgnwogxlfddimtwuiaqd`). Como a chave
disponível localmente é a **publishable key** (papel `anon`), a verificação foi feita pelo
**PostgREST**, que responde diferente conforme a estrutura:

| Prova | Resultado | Conclusão |
|---|---|---|
| `rpc/health_check` | HTTP 200 `"ok"` | projeto acessível, função instalada |
| `rpc/cpf_valido` | existe no cache de schema (`cpf_valido(cpf_txt text)`) | função **nova** do item #6 já está no banco |
| `alunos?select=cpf` | HTTP 200 (coluna existe) | item #6 aplicado |
| `professores?select=cpf` | HTTP 200 | item #6 aplicado |
| `matriculas?select=dia_vencimento` | HTTP 200 | item #11 aplicado |
| `alunos?select=coluna_inexistente_x` | HTTP 400 `PGRST100` | **controle**: prova que o 200 acima é significativo |

> `cpf_valido` não existe em nenhum arquivo de `historico/` — é marca exclusiva do `INSTALAR.sql`
> atual. Logo, a versão nova **está** aplicada.

### 20.1 Achado: `anon` conseguia executar as RPCs de financeiro

Ao chamar `POST /rest/v1/rpc/gerar_mensalidades` com `{}` (parâmetros opcionais), a resposta foi
**HTTP 200** — ou seja, o papel `anon` executou a função. Causa: o Postgres concede `EXECUTE` ao
papel `PUBLIC` em **toda** função criada; o `GRANT ... TO authenticated` **somente acrescenta** o
privilégio, não o remove.

Impacto real hoje: **nenhum** — `gerar_mensalidades` e `gerar_carne` beginam com
`IF NOT public.administrador_atual() THEN RETURN ...`, e `administrador_atual()` resolve
`auth.uid()`, que é `null` para `anon` (a chamada retornou `0`, sem gravar nada). Mas essa permissão é ampla demais e frágil.

**Correção (BLOCO 9.1, idempotente):**

```sql
REVOKE ALL ON FUNCTION public.<cada_função>() FROM PUBLIC;
```

aplicado às 11 funções de `public` (as RPCs, os helpers de RLS, `cpf_valido` e as funções de
trigger). Depois do `REVOKE`, o único `EXECUTE` liberado a `anon` é o `health_check()` — que é
proposital (o Netlify faz o health check pela rede pública).

Conferência (rodar como `postgres`):

```sql
SELECT count(*) FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
 WHERE n.nspname = 'public' AND has_function_privilege('anon', p.oid, 'EXECUTE');
-- esperado: 1 (health_check)
```

**Ação pendente:** rodar **só** o `09_grants.sql` no SQL Editor do Supabase (idempotente, 1 s).
A suíte `testes/` e o `INSTALAR.sql` completo foram revalidados localmente (nova e legada) com o
`REVOKE` — todos os testes passam.

> **Correção em 22/10/2026 (ver §22):** o `REVOKE ... FROM PUBLIC` **não bastava** — o Supabase dá
> um privilégio **explícito** de `EXECUTE` ao papel `anon` (default privileges), que sobrevive ao
> revoke de `PUBLIC`. Hoje o `anon` ainda executa as 12 funções de `public` (a consulta acima
> devolve `12`). O bloco 9 agora revoga **de `PUBLIC` e de `anon`**, e o alvo passa a ser **4**
> funções (`health_check` + as 3 auxiliares de RLS, que as políticas precisam conseguir chamar).

### 20.2 O que ainda não foi possível verificar

O conteúdo das tabelas (se há dados) **não** é legível pelo papel `anon` (todas as políticas de
`SELECT` dependem de `auth.uid()`/`administrador_atual()`; o resultado `*/0` do PostgREST é
bloqueio de RLS, não banco vazio). Para conferir, é preciso rodar a query de contagem no SQL
Editor (roda como `postgres`) ou fornecer a senha do banco para um `psql` somente-leitura.


---

## 21. Seed de demonstração — `SEED_DEMO.sql` (21/10/2026)

Script de dados para conferir a interface com conteúdo realista (o `SEED_TESTE.sql` anterior é
genérico e deixa os gráficos de progresso vazios).

### Conteúdo

| Tabela | Quantidade | Observação |
|---|---|---|
| `professores` | 5 | Marina Duarte (Piano, 3 turmas), Rafael Negreiros (Violão), Camila Sato (Canto), Bruno Tavares (Bateria), **Helena Prado (inativa — demonstra a RN14)** |
| `turmas` | 8 | 7 ativas + 1 encerrada (`Teclado Teens`, com a professora inativa) |
| `alunos` | 20 | 6 menores com responsável legal, 2 sem CPF (CPF é opcional), nomes/contatos/São Paulo |
| `matriculas` | 20 | 12 mensais em turma · 3 carnê (6x, 12x, 6x) · 2 individuais (VIP) · 1 aula avulsa · 1 trancada · 1 concluída |
| `grade_conteudos` | 8 | 3 módulos (Fundamentos, Harmonia, Performance) |
| `conteudos_ministrados` | 29 | 3 aulas por turma ativa, 1 na encerrada, 3 avulsas, 4 dos VIPs |
| `desempenhos` | 49 | Um por aluno × aula (base dos gráficos de desempenho) |
| `financeiro` | 96 | 61 mensalidades pagas · 12 atrasadas · 3 aulas avulsas (1 paga) · 3 ajustes (2 descontos negativos + 1 material) · 17 taxas de matrícula |

### Regras respeitadas

- **RN14**: a professora inativa só tem turma `encerrada` — a trava do banco (`exigir_professor_ativo_na_turma`)
  impede turma ativa com professor inativo, e o seed não tenta.
- **Item #5 (desconto)**: os ajustes negativos são `tipo = 'ajuste'`, que é a única origem de valor
  negativo permitida pelo CHECK `financeiro_check_valor`.
- **Item #6 (CPF)**: todos os CPFs gerados por `seed_cpf()` passam em `public.cpf_valido()`;
  a verificação local rodou 20 CPFs de aluno + 5 de professor + 6 de responsável, 0 inválidos.
- **Item #11 (vencimento)**: as mensalidades seguem `dia_vencimento` da matrícula
  (`competencia + (dia_vencimento - 1)`), igual à RPC `gerar_mensalidades`.
- **Item #15 (carnê)**: as parcelas reproduzem a estrutura da RPC `gerar_carne` (a última parcela
  absorve o arredondamento), com `ON CONFLICT (matricula_id, competencia, tipo) DO NOTHING`.
- **Cobranças automáticas**: a taxa de matrícula e as aulas avulsas foram deixadas para os
  triggers (`trig_financeiro_matricula`, `trig_financeiro_avulsa_insert`) criarem sozinhos.

### Idempotência e limpeza

- Rodar de novo não duplica nada: o bloco abre com uma guarda
  (`IF EXISTS (SELECT 1 FROM public.professores WHERE nome = 'Marina Duarte')`) e avisa
  "Seed demo já aplicado — nada a fazer".
- Tudo em um único `DO $$` (uma transação): ou entra inteiro, ou nada.
- O fim do arquivo traz o bloco `DELETE DE LIMPEZA` para remover a demonstração.

### Validação local (PostgreSQL 16)

`INSTALAR.sql` + `SEED_DEMO.sql` rodados em base nova: contagens exatamente como na tabela acima;
2ª execução sem efeito; `vw_progresso_turma` (37,5% por turma ativa, 12,5% na encerrada),
`vw_progresso_aluno` (25% a 37,5%), `vw_financeiro_resumo` (5 competências),
`vw_inadimplentes` e `vw_desempenho_aluno` com dados. A suíte `testes/` continua verde.

---

## 22. Revisão de segurança e pendências (22/10/2026)

Auditoria do estado do repositório e do banco de produção (sonda PostgREST com a chave `anon`,
sem login). Três achados — **dois de segurança** — e a correção da suíte de regressão.

### #16 — Vazamento de dados: as views de relatório eram lidas por visitante sem login (corrigido)

- **Causa:** o `INSTALAR.sql` foi aplicado no Supabase por volta de 21/10 13:00, mas o
  `security_invoker = true` (BLOCO 8) entrou no arquivo **às 13:28**, depois da instalação. No
  Supabase, `anon` tem `SELECT` por padrão em **todas as views** do schema `public`, e view **não
  tem RLS**: sem `security_invoker`, a view é executada com os privilégios do dono (superusuário)
  e ignora o RLS das tabelas.
- **Prova (antes da correção), via PostgREST com a chave anônima:**

  | Consulta | Antes | Depois |
  |---|---|---|
  | `vw_financeiro_resumo` | 19 linhas com valores | `[]` |
  | `vw_progresso_turma` | 18 turmas | `[]` |
  | `vw_progresso_aluno` | 18 **nomes de alunos** | `[]` |
  | `vw_desempenho_aluno` | 49 **nomes + notas** | `[]` |
  | `vw_desempenho_turma` | 22 linhas | `[]` |
  | `alunos` / `professores` (tabelas) | `[]` (RLS ok) | `[]` |

- **Correção:** rodar `INSTALAR_SUPABASE/08_views.sql` no Supabase (o bloco 8 já aplicava
  `security_invoker` às 6 views). **Feito em 22/10** — as 6 views agora devolvem `[]` para o
  visitante sem login.

### #17 — `REVOKE ... FROM PUBLIC` não tirava o `EXECUTE` do `anon` (corrigido no script)

- **Sintoma:** a conferência do §20.1 (`has_function_privilege('anon', …, 'EXECUTE')`) devolvia
  **12** — todas as funções de `public` — em vez de 1.
- **Causa:** o Supabase entrega o schema `public` com
  `GRANT ALL ON ALL FUNCTIONS IN SCHEMA public TO anon, authenticated` **e**
  `ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON FUNCTIONS TO anon`. Esse privilégio é
  **explícito** (não vem do `PUBLIC`), então `REVOKE … FROM PUBLIC` não o remove.
- **Prova (PostgreSQL 16 local):** função criada com o default privilege do Supabase →
  `REVOKE … FROM PUBLIC` → `anon` **ainda executa** (`t`) · `REVOKE … FROM PUBLIC` **e**
  `REVOKE … FROM anon` → `anon` não executa mais (`f`).
- **Correção no BLOCO 9 (`INSTALAR.sql` e `INSTALAR_SUPABASE/09_grants.sql`):**
  - revogar as 8 funções de negócio de `PUBLIC` **e de `anon`**;
  - `GRANT EXECUTE` explícito a `authenticated` para as 5 funções de **trigger** (disparadas por
    `INSERT`/`UPDATE` de quem está logado — o papel que executa a ação precisa de `EXECUTE` nelas).
- **Alvo final:** `anon` executa **4** funções — `health_check` (monitoramento) + as 3 auxiliares
  de RLS (`usuario_atual`, `administrador_atual`, `professor_atual`), que as políticas **precisam**
  conseguir chamar (sem `EXECUTE`, a consulta falha com "permissão negada" em vez de devolver
  lista vazia; são inofensivas sem login, pois `auth.uid()` é `NULL`).
- **Estado em 22/10:** o `09_grants.sql` novo **ainda não foi aplicado** no Supabase (o que o
  usuário rodou foi a versão anterior, só `FROM PUBLIC`). Falta colar o arquivo atual.

### #18 — Suíte de regressão estava vermelha (corrigido)

- `testes/sql/05_seguranca_views.sql` (criado 21/10 13:30, nunca validado) falhava com
  *"anon enxerga 19 linhas em public.vw_financeiro_resumo"*.
- **Causa:** `testes/sql/03_vencimento_carne.sql` **redefinia `auth.uid()` globalmente** com um
  uuid fixo. Como as funções de RLS são `SECURITY DEFINER`, `administrador_atual()` passava a
  devolver `true` **para qualquer papel** (inclusive `anon`) — falso positivo, não falha do SQL
  de produção (verificado: em base nova com `auth.uid()` = `NULL`, o `anon` vê 0 linhas).
- **Correção:** o mock agora imita o Supabase de verdade —
  `auth.uid()` lê o GUC de sessão `request.jwt.claim.sub` (o JWT da requisição); o teste 03 faz
  `SET request.jwt.claim.sub = '1111…'` (vale só na sessão dele) e o 05 continua "ninguém logado".
  O `mock_auth.sql` passou a aplicar `ALTER DEFAULT PRIVILEGES … GRANT EXECUTE ON FUNCTIONS TO
  anon` (como o Supabase), para o teste exercitar o cenário real: as funções **nascem**
  executáveis pelo `anon` e quem precisa negar é o `REVOKE`.
- **Novo passo no teste 05:** o `anon` deve conseguir executar **exatamente 4** funções de
  `public` (falha se != 4) — trava contra a regressão do #17.
- **Resultado:** `.\testes\run.ps1` → **TODOS OS TESTES PASSARAM** (base nova e base legada).

### Estado do banco de produção (22/10/2026)

O banco **não está vazio**: tem os dois seeds aplicados — 18 turmas, ~50 alunos com nome, 49
avaliações de desempenho e lançamentos em 19 competências (`SEED_TESTE` + `SEED_DEMO`). A cópia
local `escola_sec` (PostgreSQL 16 desta máquina) tem só o `SEED_DEMO` (5 profs · 8 turmas ·
20 alunos · 96 lançamentos · 29 aulas · 49 desempenhos) — está defasada em relação à produção.

### Pendências que restam (22/10/2026)

- 🔴 **Colar o `INSTALAR_SUPABASE/09_grants.sql` atual** no Supabase (revoke de `PUBLIC` **e** de
  `anon` + grants para `authenticated`). Conferência: esperado **4** funções executáveis pelo
  `anon` (hoje: 12). Ver §22 #17.
- 🔴 **`SUPABASE_SERVICE_ROLE_KEY`** no Netlify (Site configuration → Environment variables) e no
  `.env.local` — sem ela `/api/criar-acesso` responde 500 e o acesso do professor (RF06) não
  funciona.
- 🔴 **Supabase → Authentication → URL Configuration**: Site URL + Redirect URLs com
  `/redefinir.html` (produção e local) — senão a recuperação de senha (RF04) não volta ao app.
- 🔴 **Conferir a contagem de registros** no SQL Editor (roda como `postgres`; o `anon` não lê por
  RLS) — §20.2.
- 🟡 **Trocar a senha temporária** da conta admin `adaoelias@gmail.com`.
- 🟡 **Commit**: nada foi commitado desde 22/09 — 20 arquivos modificados e ~25 novos
  (`INSTALAR.sql`, `INSTALAR_SUPABASE/`, `historico/`, `testes/`, `scripts/`, `.github/`,
  `functions/criar-acesso.js`, `public/redefinir.html`, `public/js/vendor/`, `SEED_DEMO.sql`).
- 🟡 **Higiene do repositório:** 12 PNGs de tela na raiz e 2 `.docx` duplicados de documentação —
  definir o destino (ex.: `docs/telas/`) e deixar uma versão canônica.
- ⚪ `functions/criar-acesso.js` suporta `acao: 'vincular'` (conta já existente no Auth), mas o
  front (`professores.js`) só chama `acao: 'criar'` — falta a tela de vincular conta existente.
- ⚪ `netlify.toml` não fixa a versão do Node (decisão de produto em aberto desde o §16).

