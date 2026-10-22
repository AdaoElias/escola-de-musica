#!/usr/bin/env bash
# Regression suite for the database (INSTALAR.sql) - Linux/macOS/CI.
#
#   ./testes/run.sh
#
# Requires a local PostgreSQL and the psql client on PATH.
# Set PGHOST/PGUSER/PGPASSWORD to change the target.

set -uo pipefail
REPO="$(cd "$(dirname "$0")/.." && pwd)"
export PGHOST="${PGHOST:-localhost}"
export PGUSER="${PGUSER:-postgres}"
export PGPASSWORD="${PGPASSWORD:-postgres}"
PSQL="psql -v ON_ERROR_STOP=1 -q"

falhas=0

run_sql() { # $1 = arquivo, $2 = banco
  if ! $PSQL -d "$2" -f "$1"; then
    echo "  [FALHOU] psql em $1" >&2
    return 1
  fi
}

check() { # $1 = nome, $2 = funcao
  if "$2"; then
    echo "  [ok] $1"
  else
    echo "  [FALHOU] $1"
    falhas=$((falhas + 1))
  fi
}

new_db() { $PSQL -c "DROP DATABASE IF EXISTS $1" >/dev/null 2>&1; $PSQL -c "CREATE DATABASE $1" >/dev/null; }
drop_db() { $PSQL -c "DROP DATABASE IF EXISTS $1" >/dev/null 2>&1; }

echo ""
echo "=== 1. BASE NOVA: INSTALAR -> SEED -> INSTALAR -> SEED ==="
new_db escola_teste_nova
check "INSTALAR.sql + SEED_TESTE.sql (2x, idempotente)" {
  run_sql "$REPO/testes/sql/mock_auth.sql" escola_teste_nova &&
  run_sql "$REPO/INSTALAR.sql" escola_teste_nova &&
  run_sql "$REPO/SEED_TESTE.sql" escola_teste_nova &&
  run_sql "$REPO/INSTALAR.sql" escola_teste_nova &&
  run_sql "$REPO/SEED_TESTE.sql" escola_teste_nova
}
check "01 estrutura" { run_sql "$REPO/testes/sql/01_estrutura.sql" escola_teste_nova; }
check "02 regras CPF/desconto" { run_sql "$REPO/testes/sql/02_regras_cpf_desconto.sql" escola_teste_nova; }
check "03 vencimento e carne" { run_sql "$REPO/testes/sql/03_vencimento_carne.sql" escola_teste_nova; }
check "04 professor ativo (RN14)" { run_sql "$REPO/testes/sql/04_professor_ativo.sql" escola_teste_nova; }
check "05 seguranca (views + privilegios anon)" { run_sql "$REPO/testes/sql/05_seguranca_views.sql" escola_teste_nova; }
drop_db escola_teste_nova

echo ""
echo "=== 2. BASE LEGADA (historico/) -> INSTALAR converge ==="
new_db escola_teste_legada
check "INSTALAR.sql sobre base legada" {
  run_sql "$REPO/testes/sql/mock_auth.sql" escola_teste_legada
  for f in SCHEMA.sql MIGRACAO_ETAPA2.sql MIGRACAO_FIX_RLS.sql MIGRACAO_ETAPA5.sql MIGRACAO_ETAPA6.sql MIGRACAO_PENDENTE.sql; do
    psql -v ON_ERROR_STOP=0 -q -d escola_teste_legada -f "$REPO/historico/$f" >/dev/null 2>&1
  done
  run_sql "$REPO/INSTALAR.sql" escola_teste_legada
}
check "01 estrutura" { run_sql "$REPO/testes/sql/01_estrutura.sql" escola_teste_legada; }
drop_db escola_teste_legada

echo ""
if [ "$falhas" -eq 0 ]; then
  echo "RESULTADO: TODOS OS TESTES PASSARAM"
  exit 0
else
  echo "RESULTADO: $falhas TESTE(S) FALHARAM"
  exit 1
fi
