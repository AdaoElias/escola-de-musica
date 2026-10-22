# Regression suite for the database (INSTALAR.sql).
#
#   PowerShell : .\testes\run.ps1
#   Linux/macOS: ./testes/run.sh
#
# Requires a local PostgreSQL (default: postgres@localhost/postgres) and the
# psql/pg_dump clients on PATH. Set PGHOST/PGUSER/PGPASSWORD to change the target.
#
# Scenarios:
#   1. New base: INSTALAR -> SEED -> INSTALAR -> SEED (idempotency) + rule checks
#   2. Legacy base (historico/*.sql) -> INSTALAR converges

$ErrorActionPreference = "Stop"
$REPO = Split-Path -Parent $PSScriptRoot
if (-not $env:PGHOST) { $env:PGHOST = "localhost" }
if (-not $env:PGUSER) { $env:PGUSER = "postgres" }
if (-not $env:PGPASSWORD) { $env:PGPASSWORD = "postgres" }
$PSQL = "psql"

$falhas = 0
function Run-Sql([string]$file, [string]$db) {
  & $PSQL -v ON_ERROR_STOP=1 -q -d $db -f $file
  if ($LASTEXITCODE -ne 0) { throw "psql falhou ($LASTEXITCODE) em $file" }
}
function Check([string]$nome, [scriptblock]$bloco) {
  try {
    & $bloco
    Write-Host "  [ok] $nome"
  } catch {
    Write-Host "  [FALHOU] $nome -> $($_.Exception.Message)"
    $script:falhas++
  }
}
function New-Db([string]$nome) {
  & $PSQL -q -c "DROP DATABASE IF EXISTS $nome" | Out-Null
  & $PSQL -q -c "CREATE DATABASE $nome" | Out-Null
}
function Drop-Db([string]$nome) {
  & $PSQL -q -c "DROP DATABASE IF EXISTS $nome" | Out-Null
}

Write-Host ""
Write-Host "=== 1. BASE NOVA: INSTALAR -> SEED -> INSTALAR -> SEED ==="
New-Db "escola_teste_nova"
Check "INSTALAR.sql + SEED_TESTE.sql (2x, idempotente)" {
  Run-Sql "$REPO\testes\sql\mock_auth.sql" "escola_teste_nova"
  Run-Sql "$REPO\INSTALAR.sql" "escola_teste_nova"
  Run-Sql "$REPO\SEED_TESTE.sql" "escola_teste_nova"
  Run-Sql "$REPO\INSTALAR.sql" "escola_teste_nova"
  Run-Sql "$REPO\SEED_TESTE.sql" "escola_teste_nova"
}
Check "01 estrutura" { Run-Sql "$REPO\testes\sql\01_estrutura.sql" "escola_teste_nova" }
Check "02 regras CPF/desconto" { Run-Sql "$REPO\testes\sql\02_regras_cpf_desconto.sql" "escola_teste_nova" }
Check "03 vencimento e carne" { Run-Sql "$REPO\testes\sql\03_vencimento_carne.sql" "escola_teste_nova" }
Check "04 professor ativo (RN14)" { Run-Sql "$REPO\testes\sql\04_professor_ativo.sql" "escola_teste_nova" }
Check "05 seguranca (views + privilegios anon)" { Run-Sql "$REPO\testes\sql\05_seguranca_views.sql" "escola_teste_nova" }
Drop-Db "escola_teste_nova"

Write-Host ""
Write-Host "=== 2. BASE LEGADA (historico/) -> INSTALAR converge ==="
New-Db "escola_teste_legada"
Check "INSTALAR.sql sobre base legada" {
  Run-Sql "$REPO\testes\sql\mock_auth.sql" "escola_teste_legada"
  foreach ($f in @("SCHEMA.sql", "MIGRACAO_ETAPA2.sql", "MIGRACAO_FIX_RLS.sql",
                   "MIGRACAO_ETAPA5.sql", "MIGRACAO_ETAPA6.sql", "MIGRACAO_PENDENTE.sql")) {
    & $PSQL -v ON_ERROR_STOP=0 -q -d "escola_teste_legada" -f "$REPO\historico\$f" | Out-Null
  }
  Run-Sql "$REPO\INSTALAR.sql" "escola_teste_legada"
}
Check "01 estrutura" { Run-Sql "$REPO\testes\sql\01_estrutura.sql" "escola_teste_legada" }
Drop-Db "escola_teste_legada"

Write-Host ""
if ($falhas -eq 0) {
  Write-Host "RESULTADO: TODOS OS TESTES PASSARAM"
  exit 0
} else {
  Write-Host "RESULTADO: $falhas TESTE(S) FALHARAM"
  exit 1
}
