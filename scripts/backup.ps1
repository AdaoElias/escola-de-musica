# Backup local do banco (RNF04)
#
# Uso (PowerShell):
#   $env:DATABASE_URL = "postgresql://postgres:SUA_SENHA@db.XXXXXXXX.supabase.co:5432/postgres"
#   .\scripts\backup.ps1
#
# O dump fica em .\backups\ (fora do git - contem dados pessoais de alunos:
# CPF, endereco, data de nascimento - ver .gitignore e RNF06/LGPD).
#
# Para subir o dump para um bucket privado, use um storage com controle de acesso
# (ex.: S3 privado + URL assinada) - nunca versione o arquivo no repositorio.

param(
  [string]$Saida = ".\backups",
  [int]$Manter = 10
)

$ErrorActionPreference = "Stop"

if (-not $env:DATABASE_URL) {
  Write-Error "Defina a variavel DATABASE_URL antes de rodar (Supabase > Project Settings > Database > Connection string)."
}

if (-not (Get-Command pg_dump -ErrorAction SilentlyContinue)) {
  Write-Error "pg_dump nao encontrado. Instale o PostgreSQL client (https://www.postgresql.org/download/) ou use o container oficial."
}

if (-not (Test-Path -LiteralPath $Saida)) {
  New-Item -ItemType Directory -Path $Saida | Out-Null
}

$stamp = Get-Date -Format "yyyyMMdd-HHmmss"
$arquivo = Join-Path $Saida "escola-musica-$stamp.sql"

Write-Host "Gerando dump em $arquivo ..."
# --no-owner / --no-acl: o dump deve ser restauravel em qualquer ambiente
# --clean --if-exists: permite restaurar sobre um banco existente
$env:PGPASSWORD = ([System.Uri]$env:DATABASE_URL).UserInfo.Split(':')[1]
& pg_dump --dbname=$env:DATABASE_URL --format=plain --no-owner --no-acl --clean --if-exists --file=$arquivo

if ($LASTEXITCODE -ne 0) {
  Write-Error "pg_dump falhou (codigo $LASTEXITCODE)."
}

$tamanho = (Get-Item $arquivo).Length
Write-Host "OK: $arquivo ($([math]::Round($tamanho/1MB,2)) MB)"

# Rotacao: mantem apenas os N dumps mais recentes
$antigos = Get-ChildItem -LiteralPath $Saida -Filter "escola-musica-*.sql" |
           Sort-Object LastWriteTime -Descending | Select-Object -Skip $Manter
foreach ($a in $antigos) {
  Write-Host "Removendo dump antigo: $($a.Name)"
  Remove-Item -LiteralPath $a.FullName -Force
}

Write-Host "Backup concluido."
