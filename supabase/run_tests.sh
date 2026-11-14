#!/usr/bin/env bash
# Exécute la migration et les tests sur une base PostgreSQL jetable (variable PGURL, par défaut un serveur local).
set -euo pipefail
cd "$(dirname "$0")"
: "${PGURL:=postgresql://postgres@localhost:5432}"
DB="strasse_test_$$"
psql "$PGURL/postgres" -qc "create database $DB"
trap 'psql "$PGURL/postgres" -qc "drop database if exists $DB" >/dev/null' EXIT
psql "$PGURL/$DB" -q -v ON_ERROR_STOP=1 -f tests/mock_supabase.sql
psql "$PGURL/$DB" -q -v ON_ERROR_STOP=1 -f migrations/0001_strasse.sql
# Idempotence : la migration peut être rejouée.
psql "$PGURL/$DB" -q -v ON_ERROR_STOP=1 -f migrations/0001_strasse.sql
psql "$PGURL/$DB" -q -v ON_ERROR_STOP=1 -f tests/rls_test.sql
