#!/usr/bin/env bash
# Runs the database migrations and tenant isolation tests in a throwaway
# PostgreSQL 17 container. Requires Docker Desktop to be running.
# Usage (from the project root): bash supabase/tests/run_tests.sh
set -euo pipefail

CONTAINER=bg-schema-test
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"

docker rm -f "$CONTAINER" >/dev/null 2>&1 || true
docker run -d --name "$CONTAINER" -e POSTGRES_PASSWORD=localtest postgres:17-alpine >/dev/null
trap 'docker rm -f "$CONTAINER" >/dev/null 2>&1 || true' EXIT

for _ in $(seq 1 30); do
  docker exec "$CONTAINER" pg_isready -U postgres -q 2>/dev/null && break
  sleep 1
done
sleep 2

run_sql() {
  docker exec -i "$CONTAINER" psql -U postgres -q -v ON_ERROR_STOP=1 < "$1"
}

run_sql "$ROOT/supabase/tests/00_supabase_auth_stub.sql"
for migration in "$ROOT"/supabase/migrations/*.sql; do
  echo "Applying $(basename "$migration")"
  run_sql "$migration"
done

for test in "$ROOT"/supabase/tests/0[1-9]_*_test.sql; do
  echo "Running $(basename "$test")"
  docker exec -i "$CONTAINER" psql -U postgres -q -v ON_ERROR_STOP=1 < "$test" 2>&1 \
    | grep -E "PASS|FAIL|ERROR|ALL .*TESTS PASSED"
done
