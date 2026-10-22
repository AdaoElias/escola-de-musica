#!/usr/bin/env bash
# Backup local do banco (RNF04) - Linux/macOS/Netlify
#
#   export DATABASE_URL="postgresql://postgres:SUA_SENHA@db.XXXXXXXX.supabase.co:5432/postgres"
#   ./scripts/backup.sh
#
# O dump NAO e versionado (contem dados pessoais - ver .gitignore).

set -euo pipefail

SAIDA="${1:-./backups}"
MANTER="${2:-10}"

if [ -z "${DATABASE_URL:-}" ]; then
  echo "Defina DATABASE_URL antes de rodar." >&2
  exit 1
fi

command -v pg_dump >/dev/null 2>&1 || {
  echo "pg_dump nao encontrado." >&2
  exit 1
}

mkdir -p "$SAIDA"
stamp=$(date +%Y%m%d-%H%M%S)
arquivo="$SAIDA/escola-musica-$stamp.sql"

echo "Gerando dump em $arquivo ..."
pg_dump --dbname="$DATABASE_URL" --format=plain --no-owner --no-acl --clean --if-exists --file="$arquivo"

echo "OK: $arquivo ($(du -h "$arquivo" | cut -f1))"

ls -1t "$SAIDA"/escola-musica-*.sql | tail -n +$((MANTER + 1)) | while read -r antigo; do
  echo "Removendo dump antigo: $(basename "$antigo")"
  rm -f "$antigo"
done

echo "Backup concluido."
