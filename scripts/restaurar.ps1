# Restaurar um dump do backup (RNF04)
#
# Uso (PowerShell):
#   $env:DATABASE_URL = "postgresql://postgres:SUA_SENHA@localhost:5432/escola_restauracao"
#   .\scripts\restaurar.ps1 -Arquivo ".\backups\escola-musica-20261021-120000.sql"
#
# ATENCAO: o script roda em um banco NOVO (vazio). Com --clean, restaurar
# sobre um banco com dados apaga o conteudo existente.

param(
  [Parameter(Mandatory = $true)][string]$Arquivo,
  [string]$Banco = "escola_restauracao"
)

$ErrorActionPreference = "Stop"

if (-not (Test-Path -LiteralPath $Arquivo)) { Write-Error "Arquivo nao encontrado: $Arquivo" }
if (-not (Get-Command psql -ErrorAction SilentlyContinue)) { Write-Error "psql nao encontrado (PostgreSQL client)." }
if (-not $env:DATABASE_URL) { Write-Error "Defina DATABASE_URL." }

$env:PGPASSWORD = ([System.Uri]$env:DATABASE_URL).UserInfo.Split(':')[1]

Write-Host "Restaurando $Arquivo em $Banco ..."
& psql --dbname=$env:DATABASE_URL --file=$Arquivo --variable=ON_ERROR_STOP=1

if ($LASTEXITCODE -ne 0) { Write-Error "psql falhou (codigo $LASTEXITCODE)." }

Write-Host "Restaurado. Conferindo:"
& psql --dbname=$env:DATABASE_URL --command="SELECT count(*) AS tabelas FROM information_schema.tables WHERE table_schema='public';"
& psql --dbname=$env:DATABASE_URL --command="SELECT count(*) AS alunos FROM public.alunos;"
