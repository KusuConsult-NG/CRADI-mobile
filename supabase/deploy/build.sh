#!/usr/bin/env bash
# Regenerate supabase/deploy/schema.sql from supabase/migrations/*.sql.
#
# schema.sql is simply every migration concatenated in filename order, with a
# banner before each one. Run this after adding or editing a migration so the
# consolidated file cannot drift:
#
#     ./supabase/deploy/build.sh
#     git diff --stat supabase/deploy/schema.sql
#
# It only reads the migrations and writes schema.sql; it never touches a
# database. To verify the result, see supabase/deploy/README.md.
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
migrations="$root/supabase/migrations"
out="$root/supabase/deploy/schema.sql"

shopt -s nullglob
files=("$migrations"/*.sql)
shopt -u nullglob
if [ ${#files[@]} -eq 0 ]; then
  echo "no migrations found in $migrations" >&2
  exit 1
fi

i=0
rule='-- ============================================================================'

{
  cat <<EOF
$rule
--  CRADI / EWER — consolidated Supabase schema
$rule
--
--  GENERATED FILE — do not edit by hand.
--  Regenerate with:  ./supabase/deploy/build.sh
--  Source of truth:  supabase/migrations/*.sql
--
--  What this is
--    Every migration under supabase/migrations/, concatenated in filename
--    order, so the whole schema can be pasted into the Supabase SQL editor
--    (Dashboard > SQL Editor > New query) in one go. Nothing is added,
--    removed or rewritten: each migration appears verbatim below its banner.
--
--  Run it on an EMPTY project only.
--    The migrations create tables, types, functions and policies outright
--    (\`create table public.x (...)\`, \`create policy ...\`), so a second run,
--    or a run against a project that already has this schema, fails with
--    "already exists". If you need to re-run it, reset the database first
--    (Dashboard > Settings > General > Reset database) or drop the objects.
--
--  What it expects the project to already provide (real Supabase does):
--    * the roles \`anon\`, \`authenticated\` and \`service_role\`
--    * the \`auth\` schema with \`auth.users\` and \`auth.uid()\`
--    * the \`storage\` schema with \`storage.buckets\`, \`storage.objects\`
--      (RLS already enabled) and \`storage.foldername()\`
--    * the \`supabase_realtime\` publication
--    * a role that owns/administers the above — i.e. run it as \`postgres\`,
--      which is what the dashboard SQL editor uses. It creates triggers on
--      \`auth.users\` and policies on \`storage.objects\`.
--
--    supabase/tests/local_stubs.sql fakes these for plain-Postgres testing.
--    It is deliberately NOT part of this file: never run local_stubs.sql
--    against a real Supabase project.
--
--  Storage buckets \`report-images\` and \`profile-images\` are created by the
--  init migration (public read, 5 MB, image mime types) — no manual setup.
--
--  After a successful run the \`public\` schema holds 17 tables.
--
--  Source migrations, in the order applied:
EOF
  for f in "${files[@]}"; do
    printf -- '--    %2d. %s\n' "$((++i))" "$(basename "$f")"
  done
  printf -- '%s\n' "$rule"

  for f in "${files[@]}"; do
    printf '\n\n%s\n-- SOURCE: supabase/migrations/%s\n%s\n\n' "$rule" "$(basename "$f")" "$rule"
    cat "$f"
  done
} > "$out"

echo "wrote $out ($(wc -l < "$out") lines from ${#files[@]} migrations)"
