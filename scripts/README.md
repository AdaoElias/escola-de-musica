# Scripts de operação

| Script | Para quê |
|---|---|
| `backup.ps1` | Exporta o banco (Windows/PowerShell) — `pg_dump` com rotação (mantém 10 dumps) |
| `backup.sh` | Exporta o banco (Linux/macOS/Netlify) — mesmo comportamento |
| `restaurar.ps1` | Restaura um dump em um banco PostgreSQL local e confere o resultado |

## Como usar

```powershell
# 1. Pegue a connection string em Supabase > Project Settings > Database
$env:DATABASE_URL = "postgresql://postgres:SUA_SENHA@db.XXXXXXXX.supabase.co:5432/postgres"

# 2. Gere o backup (o dump vai para .\backups\, fora do git)
.\scripts\backup.ps1

# 3. Teste a restauração em um banco local novo
$env:DATABASE_URL = "postgresql://postgres:postgres@localhost:5432/escola_restauracao"
.\scripts\restaurar.ps1 -Arquivo ".\backups\escola-musica-20261021-120000.sql"
```

## Por que o dump não está no repositório

O dump contém **dados pessoais** dos alunos (CPF, data de nascimento, endereço, responsável).
Versioná-lo no Git publicaria esses dados e quebraria o RNF06 (LGPD). O que fica no repositório
é o **procedimento** (`scripts/` + `.gitignore`), não o dump. Para guardar os dumps fora da
máquina, use um bucket **privado** (S3/GCS) com URL assinada e rotina de expiração.

## Backup automático (plano free do Supabase)

O Supabase faz *point-in-time recovery* e dumps diários automáticos nos projetos pagos; no plano
gratuito, habilite **PITR** (Point-in-Time Recovery) em *Settings > Database* se o plano permitir
e combine com a exportação local semanal deste repositório. A verificação de que um dump é
restaurável é o que o `restaurar.ps1` faz — rode-o a cada trimestre.
