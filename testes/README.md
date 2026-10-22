# Testes

Suíte de regressão do banco (PostgreSQL) + verificação de sintaxe do front.

## Rodar localmente

```powershell
# Windows
.\testes\run.ps1

# Linux/macOS
./testes/run.sh
```

Requisitos: PostgreSQL local (padrão `postgres@localhost/postgres`) com `psql` no PATH.
Ajuste com `PGHOST`, `PGUSER`, `PGPASSWORD`.

O runner cria bancos temporários (`escola_teste_nova`, `escola_teste_legada`), roda as
verificações e **apaga tudo** no final. Nada toca no banco de produção.

## Cenários

| Cenário | O que faz |
|---|---|
| **Base nova** | `mock_auth` → `INSTALAR.sql` → `SEED_TESTE.sql` → `INSTALAR.sql` → `SEED_TESTE.sql` (prova a idempotência) |
| **Base legada** | `historico/*.sql` (SCHEMA + ETAPA2/FIX_RLS/ETAPA5/ETAPA6/PENDENTE) → `INSTALAR.sql` deve convergir |

## Arquivos de asserção

| Arquivo | Cobre |
|---|---|
| `sql/01_estrutura.sql` | 9 tabelas, 6 views, 37 políticas, 5 triggers, 11 funções, 5 constraints nomeadas e as unicidades (semântica, não por nome) |
| `sql/02_regras_cpf_desconto.sql` | #5 (ajuste negativo, inadimplência) e #6 (CPF único/validado, `responsavel_cpf` repetível) |
| `sql/03_vencimento_carne.sql` | #11 (vencimento = `dia_vencimento`) e #15 (`gerar_carne`: 6 parcelas, soma, idempotência, arredondamento) |
| `sql/04_professor_ativo.sql` | #10 / RN14 (inativar professor com turma ativa; turma ativa exige professor ativo) |

## CI

`.github/workflows/testes.yml` roda a suíte em cada push/PR, com PostgreSQL 16 como serviço, e
faz o `node --check` de todos os arquivos de `public/js/` e `functions/`.

## Front

Não há framework de teste no front (o app é JS puro sem build). A cobertura atual é:

- `node --check` em todos os `.js` (sintaxe) — no CI;
- regras de negócio testadas no banco, onde o efeito é observável;
- o HTML de cada tela e o fluxo de login continuam sendo verificados manualmente.
