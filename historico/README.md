# Arquivo de migrações (histórico)

> **Não use estes arquivos para instalar ou atualizar o banco.**
> A **fonte única** é [`../INSTALAR.sql`](../INSTALAR.sql) — idempotente, aplicável em base nova ou
> existente. Ele já contém tudo que estes arquivos faziam, mais as correções descritas em
> `../REGISTRO_SESSAO.md` §17.

Estes arquivos ficam aqui por **memória do processo** (o histórico de como o banco nasceu).
A cadeia antiga **não é re-executável**: `MIGRACAO_ETAPA2.sql:8` falha com
`relação "usuarios_auth_uid_key" já existe` quando rodada sobre o `SCHEMA.sql` atual.

---

## Quadro de estado (fonte única)

| Arquivo | O que fazia | Situação | Substituído por |
|---|---|---|---|
| `SCHEMA.sql` | Tabelas, enums, views de relatório, RLS inicial | aplicado no Supabase (22/09/2026) — **histórico** | `INSTALAR.sql` |
| `MIGRACAO_ETAPA2.sql` | Funções `usuario_atual`/`administrador_atual`/`professor_atual`, `health_check`, RLS em todas as tabelas | aplicado | `INSTALAR.sql` (BLOCO 5 e 6) |
| `MIGRACAO_FIX_RLS.sql` | Funções de RLS como `SECURITY DEFINER` (corrige "stack depth limit exceeded") | aplicado | `INSTALAR.sql` (BLOCO 5) |
| `MIGRACAO_ENDERECO.sql` | Colunas `endereco, bairro, cidade, cep` em `professores`/`alunos` | aplicado | `INSTALAR.sql` (BLOCO 2) |
| `MIGRACAO_CPF_NASCIMENTO.sql` | Colunas `cpf`/`nascimento` | aplicado | `INSTALAR.sql` (BLOCO 2) |
| `MIGRACAO_ETAPA4.sql` | Views `vw_progresso_turma`/`vw_progresso_aluno` | **equivalente à parte 2 do `MIGRACAO_PENDENTE.sql`** — as duas versões criam views idênticas | `INSTALAR.sql` (BLOCO 8) |
| `MIGRACAO_ETAPA5.sql` | RPC `gerar_mensalidades()`, índices parciais do financeiro | aplicado | `INSTALAR.sql` (BLOCO 7 e 4) |
| `MIGRACAO_ETAPA6.sql` | RPC `gerar_carne()`, trigger de taxa de matrícula | aplicado | `INSTALAR.sql` (BLOCO 7) |
| `MIGRACAO_PENDENTE.sql` | `FIX_RLS` + **as mesmas views do ETAPA4** | aplicado (22/09/2026) | `INSTALAR.sql` |

**Nenhuma pendência de banco** fora do `INSTALAR.sql`: as views de progresso do ETAPA4 já existem no
Supabase (foram criadas pelo `MIGRACAO_PENDENTE.sql`).

---

## Como atualizar o banco de produção

1. Supabase > **SQL Editor** > cole o conteúdo de `../INSTALAR.sql` > **Run**.
2. Pronto. O script normaliza o schema sem apagar dados e pode ser rodado quantas vezes quiser.
3. Se aparecer `ADVERTÊNCIA: CPF duplicado/inválido`, o script **ainda termina sem erro** — corrija
   os dados apontados na mensagem e rode de novo (ver `../REQUISITOS.md` §9.1).

## Dados de teste

`../SEED_TESTE.sql` (idempotente) — 10 professores, 10 turmas, 30 alunos, 30 matrículas e as
parcelas do carnê. Pode ser aplicado em qualquer momento; não repete registros.
