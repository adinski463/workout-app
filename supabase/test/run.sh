#!/usr/bin/env bash
# Apply the migrations to a throwaway Postgres database and run the RLS tests.
#
# This does not need a Supabase project — 00_shim.sql stands in for the pieces
# Supabase would provide (the auth schema, auth.uid(), the standard roles).
set -euo pipefail

DB="${WORKOUT_TEST_DB:-workout_test}"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

run() { su postgres -c "psql -v ON_ERROR_STOP=1 -q $*"; }

echo "==> recreating database $DB"
run "-c 'drop database if exists $DB'"
run "-c 'create database $DB'"

echo "==> applying shim"
run "-d $DB -f $ROOT/supabase/test/00_shim.sql"

echo "==> applying migrations"
for f in "$ROOT"/supabase/migrations/*.sql; do
  echo "    $(basename "$f")"
  run "-d $DB -f $f"
done

echo "==> running tests"
run "-d $DB -f $ROOT/supabase/test/01_rls_test.sql"
