# 🗂️ Escola de Música
**Status:** Em andamento (roadmap RF01–RF35 concluído; migrações consolidadas em `INSTALAR.sql` e suíte de regressão versionada em `testes/` + CI) | **Período:** 21/09/2026 — 22/10/2026 (commits no GitHub: 21–22/09/2026 e 22/10/2026) | **Repositório:** https://github.com/AdaoElias/escola-de-musica

## 🎯 Resumo
Sistema web de gestão para uma escola de música com turmas coletivas e aulas individuais: cadastros, grade de conteúdos, lançamento de aulas com desempenho, financeiro (mensal, avulsa e carnê 1x/6x/12x) e relatórios com gráficos SVG.
Rodando em 100% nos planos gratuitos (Netlify + Supabase), sem framework de front-end, sem etapa de build e sem ORM.
Cobertura funcional completa (RF01–RF35) em ~2 semanas-calendário, com o banco como fonte única de verdade e segurança por Row Level Security.

## 🎨 Proposta Inicial
**Escopo:** substituir planilhas e controle manual de uma escolinha de música por um sistema próprio que cobrisse o ciclo completo — cadastro de professores e alunos, turmas e matrículas (coletiva e individual), grade de conteúdos, registro de aulas, financeiro e relatórios de desempenho.

**Público-alvo:** administrador/diretor da escola (opera tudo) e professores (lançam aulas e avaliam desempenho das próprias turmas/alunos, sem acesso ao financeiro).

**Funcionalidades previstas:** dois perfis de acesso (Admin e Professor); cobrança mensal por padronagem como padrão e aula avulsa restrita à matrícula individual; grade de conteúdos única e compartilhada, com progresso independente por turma/matrícula; cobrança automática de aula avulsa disparada pelo próprio lançamento da aula; carnê/recibo imprimível; gráficos de desempenho e resumo financeiro; exportação CSV.

**Diferencial:** stack deliberadamente sem framework (HTML/CSS/JS puro + Functions), que entrega um sistema completo dentro do custo zero do Netlify/Supabase e com RLS no banco — a segurança dos dados não depende do front-end.

**Antes de começar:** levantamento comparativo de Moodle, Google Classroom e Canvas LMS (tecnologias, prós e contras), concluindo que as três plataformas são genéricas demais ou fechadas para o fluxo específico de uma escolinha; decisão de construir sistema próprio.

## 🛠️ Stack Técnica
| Camada | Tecnologia | Versão |
|--------|-----------|--------|
| Linguagem | JavaScript (ES Modules), HTML5, CSS3, SQL (PL/pgSQL) | — |
| Backend | Netlify Functions (Node.js, serverless) — `hello`, `health`, `client-config`, `criar-acesso` | Node 24 local / runtime padrão Netlify ⚠️ não fixado no `netlify.toml` |
| Frontend | HTML5 + CSS3 + JavaScript puro (12 telas, sem framework, sem build step) | — |
| Frontend (CDN) | `@supabase/supabase-js` importado de `esm.sh` | 2.45.0 (versão fixada na URL) |
| Banco | Supabase (PostgreSQL) + Supabase Auth — 9 tabelas, 8 ENUM, 4 views, RLS em todas | PostgreSQL ⚠️ versão não informada |
| ORM/Query builder | Nenhum — acesso via PostgREST (`supabase-js`) + RPC PL/pgSQL | — |
| Infra/Deploy | Netlify (site estático + functions) com deploy automático a partir do GitHub; `netlify.toml` com redirect `/api/*` | netlify-cli ^19.0.0 |
| Autenticação | Supabase Auth (e-mail/senha, sessão JWT Bearer) + Row Level Security no PostgreSQL; recuperação de senha por e-mail | — |
| APIs externas | ViaCEP (busca de endereço por CEP) | — |
| Ferramentas | Git, GitHub, Netlify CLI, Supabase Dashboard/SQL Editor, `node --check` (validação de sintaxe) | — |
| Dependências npm | `@supabase/supabase-js` ^2.45.0 (produção) · `netlify-cli` ^19.0.0 (dev) | — |

## 🐛 Erros Encontrados & Corrigidos
| # | Erro | Causa Raiz | Solução | Lição |
|---|------|-----------|---------|-------|
| 1 | Site retornava **401 em todas as rotas** logo após o primeiro deploy | Netlify com **Site Protection (Password)** ativo, exigindo senha também nas rotas da API | Desativar o Site Protection no painel do Netlify | Em hospedagem com "site protegido", testar o redirecionamento de `/api/*` separadamente do HTML |
| 2 | Variáveis de ambiente não chegavam à Function; `/api/health` devolvia `definida` em vez do valor | Bug de código: o handler montava literalmente `{ url: 'definida' }` em vez de ler `process.env` | Ler `process.env.SUPABASE_URL` / `SUPABASE_PUBLISHABLE_KEY` e normalizar a URL (remover `/rest/v1/` e prefixar `https://`) | Nunca interpolar string fixa no lugar do valor da env var; o sintoma foi um falso "problema de configuração" |
| 3 | **Login retornava HTTP 400 mesmo com e-mail e senha corretos** | `public/js/auth.js` enviava `{ email, senha }`; o Supabase Auth exige `{ email, password }` | Corrigir para `signInWithPassword({ email, password: senha })` | Ler o erro real da API (o front escondia a mensagem) foi o que isolou o bug em minutos |
| 4 | `senha_hash NOT NULL` impedia vincular o admin à tabela `usuarios` | Coluna criada com a premissa de hash local, mas a senha é gerenciada pelo Supabase Auth | `ALTER TABLE usuarios ALTER COLUMN senha_hash DROP NOT NULL` | Modelar o schema a partir de quem é a fonte de verdade da senha (o Auth), e não o contrário |
| 5 | Todo CRUD logado estourava **"stack depth limit exceeded"** | Recursão de RLS: as funções `usuario_atual()`/`administrador_atual()` liam `usuarios`, e a policy da própria tabela chamava a função de novo, infinitamente | Converter as funções auxiliares em `SECURITY DEFINER` (MIGRACAO_FIX_RLS.sql) | Funções de policy nunca devem ser `SECURITY INVOKER` quando leem a própria tabela protegida — revisar RLS sempre no modo "usuário logado real" |
| 6 | `datalist` de instrumentos/formações não aparecia na tela de professores/turmas | `popularInstrumentos()` e `popularFormacoes()` tinham sido colocadas dentro do bloco de *submit* por engano | Mover as funções para o carregamento da página | Funções que populam a tela não podem viver dentro de handlers de envio |
| 7 | Modal de cadastro não centralizado no viewport | `<dialog>` sem `margin: auto` (estilo nativo do navegador) | CSS com `margin: auto` no modal | Componente de modal precisa de estilo próprio, não do padrão do `<dialog>` |
| 8 | Carnê imprimindo com colunas quebradas / altura errada na folha A4 | Layout de canhotos não considerava a altura útil da página | Grid com colunas `1fr` e altura calculada para 5 linhas por A4 | Todo documento A4 precisa de teste de impressão real, não só de preview em tela |

## ⭐ Avaliação da Stack
| Critério | Nota | Comentário |
|----------|------|-----------|
| Facilidade de aprendizado | 5 | HTML/CSS/JS puro e Supabase com SQL explícito: qualquer dev web sobe em horas, sem bundler, sem `node_modules` no front |
| Produtividade no desenvolvimento | 4 | `supabase-js` + RLS entregam CRUD com segurança pronta; perde-se em tipagem, validação e reuso (muitas linhas repetidas entre CRUDs) |
| Documentação/Comunidade | 4 | Supabase e Netlify têm documentação extensa e comunidade ativa; o custo é a curva de RLS, que é específica |
| Performance percebida | 3 | Resposta imediata por não haver build, mas sem paginação real, cache ou índices compostos; RLS avalia policy por linha e o front filtra dados |
| Você usaria de novo? | Sim | Para o escopo MVP de uma única escola (custo zero, time de 1 pessoa, regras não complexas); com ressalvas para produto multi-tenant |

## 💡 Conclusões & Recomendações
- **Recomendaria esta stack para:** produto interno de baixa escala, protótipo funcional, MVP de custo zero e time de desenvolvimento de uma pessoa. Supabase entrega banco, auth, RLS e REST em um só lugar, e o "sem build" elimina uma classe inteira de problemas de CI/CD.
- **Evitaria se:** o time crescer (vários devs editando o mesmo HTML/JS sem framework), houver necessidade de tipagem forte, testes de ponta a ponta ou relatórios analíticos pesados — aí o custo sai no refactor do front, não no banco.
- **Aprendizado principal:** a segurança do sistema foi conquistada no banco, não no front — e isso só funciona se as funções de RLS forem `SECURITY DEFINER`; sem isso, o oposto aconteceu com o bug mais caro do projeto (erro #5), que derrubou a aplicação inteira em um único commit.
- **Segundo aprendizado:** regra de negócio crítica deve morar no banco (triggers + RPC + índices únicos parciais), não no JavaScript. A cobrança de aula avulsa e o cancelamento por RN08 só são confiáveis porque estão em trigger.
- **Terceiro aprendizado:** banco como fonte de verdade exige "install reproduzível" — um `SCHEMA.sql` único e idempotente. Hoje o projeto tem 7 arquivos de migração, o que torna qualquer ambiente novo um trabalho manual.
- **Próximos passos sugeridos:** (1) consolidar as migrações em um script único; (2) criar testes das RPCs de financeiro e das policies de RLS; (3) versionar o backup (RNF04 ainda sem evidência); (4) resolver as divergências de schema listadas na revisão crítica.

## 🔖 Tags
`#javascript` `#html5` `#css3` `#nodejs` `#netlify-functions` `#serverless` `#supabase` `#postgresql` `#row-level-security` `#saas-baas` `#vanilla-js` `#sem-build`

---

## 🔎 Revisão Crítica — Inconsistências e Pontos a Detalhar

**Inconsistências técnicas encontradas**

1. **`SCHEMA.sql` não é instalável de forma completa.** Ele se declara "baseline ETAPA6", mas **não** contém as funções `gerar_mensalidades()`, `gerar_carne()`, `gerar_financeiro_avulsa()`, `gerar_financeiro_matricula()` nem os triggers correspondentes — elas só existem em `MIGRACAO_ETAPA5.sql`/`MIGRACAO_ETAPA6.sql`. Um ambiente novo instalado só com `SCHEMA.sql` (como sugere o `REQUISITOS.md` §9) fica **sem mensalidade automática e sem carnê**. → Consolidar tudo num script idempotente único (`MIGRACAO_INICIAL.sql` ou `SCHEMA.sql` completo).
2. **Estado das migrações contraditório dentro do `REGISTRO_SESSAO.md`.** §9 e §10 dizem que ETAPA5/ETAPA6 "NÃO aplicadas"; §14 diz "já aplicadas"; §14 também diz "ETAPA4 pendente" enquanto §15 afirma "nenhuma pendência de banco restante". → Um quadro único (arquivo × data de aplicação × hash) elimina a dúvida.
3. **`MIGRACAO_ETAPA4.sql` × `MIGRACAO_PENDENTE.sql`.** As views `vw_progresso_turma`/`vw_progresso_aluno` foram criadas em `MIGRACAO_PENDENTE.sql`; o ETAPA4 parece redundante. → Arquivar o ETAPA4 ou declarar a equivalência.
4. **Matrícula individual duplicada é possível.** O `UNIQUE (aluno_id, turma_id, tipo)` de `matriculas` **não protege** o caso individual: em PostgreSQL, `NULL ≠ NULL` dentro de índice único, e `turma_id` é NULL para `tipo='individual'`. O front também não valida duplicidade (`matriculas.js` faz `insert` direto). → Índice único parcial: `CREATE UNIQUE INDEX uq_matricula_individual ON matriculas (aluno_id, professor_id) WHERE turma_id IS NULL;` — depois de decidir a regra: 1 individual por aluno ou 1 por professor?
5. **RF29 (desconto) é irrepresentável.** `financeiro.valor` tem `CHECK (valor >= 0)` e cancelamento é model's `status='cancelada'` — não há como lançar um desconto negativo. → Permitir valor negativo ou modelar o desconto como lançamento positivo compensatório.
6. **CPF sem unicidade nem validação.** `alunos.cpf` e `professores.cpf` são `TEXT` livres, aceitando duplicidade e dígitos inválidos. → `UNIQUE` parcial (ignorando NULL) + validação dos dígitos verificadores no front.
7. **Versão do cliente Supabase duplicada em dois lugares.** `public/js/supabase.js` importa `https://esm.sh/@supabase/supabase-js@2.45.0` (versão fixada na URL, CDN de terceiros no caminho crítico de runtime) enquanto o `package.json` usa `^2.45.0`. Divergência silenciosa + dependência de CDN. → Import map local ou o mesmo range nos dois lados.
8. **`usuarios.senha_hash` é coluna morta.** Com a senha gerenciada pelo Auth, ela ficou nullable e sem uso (restou apenas o `DROP NOT NULL`). → Remover do schema ou marcar como legado em comentário.
9. **`grade_conteudos.tempo_estimado` é `INTERVAL`, mas a UI grava minutos.** Risco de conversão (7 = 7 minutos ou 7 dias?). → Padronizar `INTEGER` em minutos ou gravar `make_interval(mins => ?)`.
10. **`turmas.professor_id` é `NOT NULL`, mas o professor pode ser inativado.** `professores.ativo = false` deixa turmas e matrículas órfãs sem aviso no painel (que só alerta "turmas sem aulas"). → Bloquear a inativação com turmas ativas ou sinalizar explicitamente.
11. **Vencimento da mensalidade ignora o `dia_vencimento`.** Em `gerar_mensalidades()` o vencimento é sempre `(competência + 1 mês) - 1 dia`; o `dia_vencimento` (1–28, default 5) configurado na matrícula só é usado pelo carnê. → Alinhar as duas regras ou documentar a diferença explicitamente.
12. **Ausência de testes automatizados e de CI de teste.** A validação é apenas `node --check` (sintaxe). Os pontos de maior risco — `gerar_mensalidades` (competência × vencimento), `gerar_carne` (arredondamento da última parcela), trigger de aula avulsa (RN08) e as policies de RLS — não têm nenhum teste. → `pgTAP`/`pg_prove` para as RPCs e smoke test no Netlify.
13. **RNF04 (backup) sem evidência no repositório.** Não há script de exportação local nem registro de backup automático habilitado. → Versionar um `pg_dump` e uma rotina de restauração testada.
14. **`MIGRACAO_CPF_NASCIMENTO.sql` e `MIGRACAO_ENDERECO.sql` são incrementais fora da linha principal.** O `SCHEMA.sql` já contêm as colunas, mas os arquivos continuam no repositório — risco de reexecutá-los em base já consolidada. → Arquivar os consumidos.

### Situação das inconsistências (21/10/2026)

| # | Inconsistência | Situação | Como foi resolvido |
|---|---|---|---|
| 1 | `SCHEMA.sql` não instalável sozinho | ✅ resolvido | `INSTALAR.sql` — fonte única, idempotente (base nova ou existente) |
| 2 | Estado das migrações contraditório | ✅ resolvido | Quadro único em `historico/README.md` + §14 do `REGISTRO_SESSAO.md` |
| 3 | `MIGRACAO_ETAPA4` × `MIGRACAO_PENDENTE` | ✅ resolvido | Views idênticas — ambos arquivados em `historico/`; `INSTALAR.sql` cria as views |
| 4 | Matrícula individual duplicada | ✅ resolvido | `uq_matriculas_individual` (índice único parcial) + validação no `matriculas.js` |
| 5 | RF29 (desconto) irrepresentável | ✅ resolvido | `ajuste` aceita valor negativo; `financeiro_check_valor` reescrito; ajuste não é inadimplência |
| 6 | CPF sem unicidade nem validação | ✅ resolvido | `public.cpf_valido()` + CHECKs + `uq_alunos_cpf`/`uq_professores_cpf`; validação no front |
| 7 | Cliente Supabase duplicado | ✅ resolvido | Cliente **vendorizado** em `public/js/vendor/` (sem CDN no runtime) + versão única (`2.45.0`) nos dois lados |
| 8 | `usuarios.senha_hash` morta | ✅ resolvido | Marcada como **legada** no schema e nos requisitos (remover é irreversível e sem ganho) |
| 9 | `tempo_estimado` (INTERVAL × minutos) | ✅ resolvido | Constraint `grade_conteudos_tempo_estimado_check` (0 < valor ≤ 12h) + conversão explícita no front |
| 10 | Professor inativado com turmas ativas | ✅ resolvido | RN14: triggers no banco + aviso no painel/lista de turmas |
| 11 | Vencimento ignora `dia_vencimento` | ✅ resolvido | `gerar_mensalidades` usa a mesma regra do carnê |
| 12 | Sem testes automatizados | ✅ resolvido | Suíte de regressão versionada em `testes/` + CI (`.github/workflows/testes.yml`) |
| 13 | RNF04 (backup) sem evidência | ✅ resolvido | `scripts/backup.*` e `scripts/restaurar.ps1` versionados (o dump não vai para o Git — LGPD) |
| 14 | Incrementais fora da linha principal | ✅ resolvido | Arquivados em `historico/` com quadro de estado |
| **15** | *(novo)* RPC `gerar_carne` quebrada | ✅ resolvido | Referência ambígua `matricula_id` corrigida — o carnê nunca era gerado pela tela |

Detalhe de cada correção em `REGISTRO_SESSAO.md` §17.

**Pontos que vale detalhar melhor**
- Datas oficiais de início e fim do projeto (o log de commits cobre 21–22/09/2026, mas o registro fala em 21/09 — 09/10; há trabalho não commitado: `functions/criar-acesso.js`, `public/redefinir.html`, `PadraoDocumentacao.md`).
- Versão exata do PostgreSQL do Supabase e do runtime Node usado no Netlify (não fixado no `netlify.toml`).
- Se a cobrança de aula avulsa está ativa em produção (o seed injeta parcelas direto em `financeiro`, contornando o caminho normal).
- Política de retenção/LGPD: o sistema guarda CPF, data de nascimento, endereço e responsável de menores, mas não há registro de consentimento, prazo de retenção ou rotina de descarte (RNF06).
- Quem opera a escola no dia a dia e como o admin é treinado — não há manual de uso, apenas `REQUISITOS.md` e o registro de sessão.
- Observabilidade: sem Sentry/Logtail, erros de front ou de Function ficam invisíveis (só há o toast e o `health`).
- Testes manuais existentes: `SEED_TESTE.sql` cobre 10 professores, 10 turmas, 30 alunos e 30 matrículas, mas **não** insere `conteudos_ministrados`/`desempenhos` — os gráficos de desempenho saem vazios até haver aulas reais lançadas.

## 🧭 Inferência de Stack — Como a Stack foi Deduzida

| Evidência no projeto | Inferência |
|---|---|
| `netlify.toml` com `publish = "public"` e `[[redirects]] /api/* → /.netlify/functions/:splat` | Deploy em **Netlify** com site estático + **Functions** (sem build step: `echo Static site - no build step`) |
| `functions/*.js` com `exports.handler` e `require('@supabase/supabase-js')` | Runtime **Node.js** (CommonJS) — `@supabase/supabase-js` ^2.45.0 como única dependência de produção |
| `public/js/supabase.js` importando `https://esm.sh/@supabase/supabase-js@2.45.0` | Frontend **sem bundler**, consumindo o cliente do **Supabase** via CDN/ESM — confirma "HTML + CSS + JS puro" |
| `SCHEMA.sql` com `CREATE TYPE`, `NUMERIC`, `INTERVAL`, `SECURITY DEFINER`, `CREATE POLICY` | Banco **PostgreSQL** (plano **Supabase**), com **PL/pgSQL** para as regras de negócio e **RLS** como mecanismo de segurança |
| `public/js/auth.js` usando `signInWithPassword`, `resetPasswordForEmail`, `updateUser` | Autenticação pelo **Supabase Auth** (e-mail/senha, JWT Bearer), sessão persistida no navegador |
| `MIGRACAO_ETAPA5/6.sql` com `CREATE UNIQUE INDEX ... WHERE tipo = 'mensalidade'` | Regras críticas no **banco** (índices únicos parciais, triggers, RPCs), sem ORM e sem migrations framework |
| Ausência de `tsconfig.json`, `package-lock` com bundler, `vite.config`, `webpack` | **Sem framework, sem compilação, sem TypeScript** — o front é modular por ES Modules nativos |
| `REQUISITOS.md` RNF03 ("permanecer nos planos gratuitos") | **Serverless/BaaS** como decisão arquitetural: custo zero e sem servidor para gerenciar |
| `public/js/graficos.js` (SVG montado à mão) e `public/js/csv.js` (BOM UTF-8 para Excel pt-BR) | Dependências externas **deliberadamente evitadas** — Everything-vanilla por escolha, não por limitação |

**Stack resultante (confiança alta):** HTML5 + CSS3 + JavaScript ES Modules · Netlify Functions (Node.js) · Supabase (PostgreSQL + Auth) · Git/GitHub como CI/CD. **Itens de confiança baixa/média:** versão exata do PostgreSQL e do runtime Node, se há ou não plano de migração para um framework, e a existência de ambiente de homologação (staging).
