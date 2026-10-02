#!/usr/bin/env bash
# Loads the schema (+ demo seed) into a hosted Postgres such as Supabase.
# Usage: put  DATABASE_URL=postgresql://...  in .deploy.env (git-ignored), then:  scripts/apply_db.sh [--no-seed]
# WARNING: the migration is not idempotent. Run it once on an empty database.
set -euo pipefail
cd "$(dirname "$0")/.."
[ -f .deploy.env ] && set -a && . ./.deploy.env && set +a
: "${DATABASE_URL:?Set DATABASE_URL in .deploy.env}"

# Passwords with characters like @ / # break URLs, so URL-encode the password (split at the last @).
DATABASE_URL=$(python3 - <<'PY'
import os, urllib.parse
raw = os.environ["DATABASE_URL"]
scheme, rest = raw.split("://", 1)
cred, host = rest.rsplit("@", 1)
user, pw = cred.split(":", 1)
print(f"{scheme}://{user}:{urllib.parse.quote(urllib.parse.unquote(pw), safe='')}@{host}")
PY
)
export DATABASE_URL
IMAGE="${PSQL_IMAGE:-postgres:16-alpine}"

files=(-f /sql/migrations/0001_init.sql)
[ "${1:-}" = "--no-seed" ] || files+=(-f /sql/seed.sql)

echo "Applying to $(echo "$DATABASE_URL" | sed -E 's#://[^@]*@#://***@#')"
docker run --rm -v "$PWD/supabase:/sql:ro" -e DATABASE_URL "$IMAGE" \
  sh -c 'psql "$DATABASE_URL" -v ON_ERROR_STOP=1 "$@"' _ "${files[@]}"
echo "Done."
