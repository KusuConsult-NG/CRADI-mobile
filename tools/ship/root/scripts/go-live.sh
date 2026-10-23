#!/usr/bin/env bash
#
# Takes a permission or schema change live, in the one order that works.
#
#   ./scripts/go-live.sh              show what each step would do, change nothing
#   ./scripts/go-live.sh --apply      do it
#
# Four steps. The order is not a preference:
#
#   1. provision   creates any column the plan declares and the project
#                  lacks. Until a column exists every write to it is
#                  refused, so this is first.
#   2. functions   pushes the code that enforces the rules. Before this,
#                  a rule change is in the repository and nowhere else.
#   3. migrate     re-derives the stored ACLs and account labels on rows
#                  that already exist. An Appwrite ACL is a list written
#                  once, at creation, not a rule evaluated on read — so a
#                  change to `reportAcl` governs the next report and no
#                  existing one. Account labels have the same problem from
#                  the other side: `syncLabels` makes an account correct
#                  from its next profile edit onward, so a coordinator
#                  nobody edits again never gets their LGA label at all.
#   4. min-version raises or lowers the `app_min_version` gate.
#
# Running 3 before 2 re-derives permissions from the rules the project is
# still running — the old ones. Running 2 before 1 deploys code whose
# writes are refused. Hence one script rather than four commands and a
# note about the order.
#
# See docs/IMPLEMENTATION.md §3 for what the scopes are, and §9 for the
# rest of the deployment picture.
#
set -eu

say()  { printf '\n\033[1m== %s\033[0m\n' "$*"; }
note() { printf '   %s\n' "$*"; }
die()  { printf '\n\033[31merror:\033[0m %s\n' "$*" >&2; exit 1; }

APPLY=0
[ "${1:-}" = "--apply" ] && APPLY=1

# ── Where the tooling is ─────────────────────────────────────────────────
#
# Walked up from this script rather than assumed, and it accepts both
# layouts: this repository, where the mobile app is under `mobile/`, and
# the mobile repository on its own. One file, so the two cannot drift.
HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT=''; INFRA=''; LAYOUT=''
d="$HERE"
while [ "$d" != '/' ]; do
  if [ -f "$d/mobile/infra/appwrite/provision.mjs" ]; then
    ROOT="$d"; INFRA='mobile/infra/appwrite'; LAYOUT='monorepo'; break
  fi
  if [ -f "$d/infra/appwrite/provision.mjs" ]; then
    ROOT="$d"; INFRA='infra/appwrite'; LAYOUT='mobile'; break
  fi
  d="$(dirname "$d")"
done
[ -n "$ROOT" ] || die "cannot find infra/appwrite above $HERE.
  Run this from inside the checkout."
cd "$ROOT"
[ -f "$INFRA/fix-report-permissions.mjs" ] || die "$INFRA has no
  fix-report-permissions.mjs — this checkout predates the permission
  migration. Pull first."

# ── Credentials ──────────────────────────────────────────────────────────
#
# Read from a file, never from the command line: an inline
# APPWRITE_API_KEY=... goes into your shell history and from there into
# whatever reads it next.
ENVFILE="${ENVFILE:-$HOME/.cradi/appwrite-cloud.env}"
if [ -z "${APPWRITE_API_KEY:-}" ]; then
  [ -f "$ENVFILE" ] || die "no credentials.
  Either source them first, or put them in $ENVFILE:
    APPWRITE_ENDPOINT, APPWRITE_PROJECT_ID, APPWRITE_API_KEY,
    TERMII_API_KEY, TERMII_SENDER_ID
  Point ENVFILE elsewhere if yours lives somewhere else."
  set -a
  # shellcheck disable=SC1090
  . "$ENVFILE"
  set +a
fi
: "${APPWRITE_PROJECT_ID:?not set}"
: "${APPWRITE_API_KEY:?not set}"
# `deploy.mjs` has no default for this, unlike the other scripts.
export APPWRITE_ENDPOINT="${APPWRITE_ENDPOINT:-https://fra.cloud.appwrite.io/v1}"
DB="${APPWRITE_DATABASE_ID:-cradi}"

# ── The SMS credentials, before anything is touched ──────────────────────
#
# Step 2 DELETES every variable on each Function before writing the set it
# knows about, because an Appwrite Function variable is addressed by a
# generated id and there is no upsert. So a deploy from a shell without
# the Termii pair does not merely fail to set them — it removes the pair
# that was there, and the outbox drain then skips every authority SMS
# silently.
#
# `deploy.mjs` refuses in that case, which is the real guard. This check
# exists so you find out before step 1 rather than after it.
if [ -z "${TERMII_API_KEY:-}" ] || [ -z "${TERMII_SENDER_ID:-}" ]; then
  printf '\n\033[31mstop:\033[0m TERMII_API_KEY and TERMII_SENDER_ID are not set.\n'
  note ''
  note 'Step 2 would delete whatever the Functions currently hold for them,'
  note 'turning off every authority SMS. After that only Termii can reissue'
  note 'them.'
  note ''
  note 'Read the current values first — Appwrite console -> Functions ->'
  note 'worker -> Settings -> Variables — and add both to your env file.'
  note ''
  note 'If this project genuinely has no SMS yet, say so deliberately:'
  note '  ALLOW_SMS_OFF=1 ./scripts/go-live.sh --apply'
  [ -n "${ALLOW_SMS_OFF:-}" ] || exit 1
  note ''
  note 'ALLOW_SMS_OFF is set — continuing with SMS off.'
fi

say 'Target'
note "endpoint  $APPWRITE_ENDPOINT"
note "project   $APPWRITE_PROJECT_ID"
note "database  $DB"
note "checkout  $ROOT  ($LAYOUT layout)"
note "revision  $(git rev-parse --short HEAD 2>/dev/null || echo '?')"
if [ "$APPLY" -eq 0 ]; then
  printf '\n\033[33m   Dry run. Nothing below will be changed.\033[0m\n'
  note 'Re-run with --apply when the plan reads right.'
fi

# ── 1. Columns ───────────────────────────────────────────────────────────
say '1/4  Provision — columns the plan declares'
if [ "$APPLY" -eq 1 ]; then
  # Idempotent: every step checks before it writes and reports
  # created / exists, so a half-finished run is resumed by running again.
  node "$INFRA/provision.mjs"
else
  note "would run: node $INFRA/provision.mjs"
  note '(--dry-run prints the whole plan offline, against an imagined empty project)'
fi

# ── 2. Functions ─────────────────────────────────────────────────────────
say '2/4  Deploy — the code that enforces the rules'
if [ "$LAYOUT" = 'monorepo' ]; then
  FUNCTIONS_CMD='./scripts/deploy.sh functions'
else
  FUNCTIONS_CMD="node $INFRA/local/deploy.mjs"
fi
if [ "$APPLY" -eq 1 ]; then
  # Through deploy.sh where it exists, so there is one definition of how
  # the Functions are deployed rather than two that can disagree.
  sh -c "$FUNCTIONS_CMD"
  note 'Deployed. The new rules apply to every write from here on.'
else
  note "would run: $FUNCTIONS_CMD"
fi

# ── 3. Existing rows ─────────────────────────────────────────────────────
say '3/4  Migrate — re-derive ACLs and labels on existing rows'
# Always dry-run first and show it, even under --apply. This rewrites
# permissions on live reports; seeing the counts beforehand is the
# difference between a migration and a surprise.
#
# Its status is captured rather than left to `set -e`: this is the only
# step that reads the whole reports table, so it is the one that trips
# over a wrong key or a dropped connection — and under `set -e` that
# killed the script before step 4 printed, losing instructions for a step
# with nothing to do with it.
MIGRATE_OK=1
node "$INFRA/fix-report-permissions.mjs" || MIGRATE_OK=0
if [ "$MIGRATE_OK" -eq 0 ]; then
  note ''
  note 'The migration could not read the project (see above). Steps 1 and 2'
  note 'are unaffected. Usual causes: a wrong or revoked API key, or'
  note 'APPWRITE_ENDPOINT naming the wrong region.'
  note 'Nothing was migrated; re-run when it is fixed — this is idempotent.'
elif [ "$APPLY" -eq 1 ]; then
  printf '\n   The above is what will change. Apply it? [y/N] '
  read -r answer
  case "$answer" in
    y|Y|yes|YES) node "$INFRA/fix-report-permissions.mjs" --apply ;;
    *)
      note 'Skipped. Nothing was migrated; steps 1 and 2 stand.'
      note 'Run this again to pick it up — the script is idempotent.'
      ;;
  esac
fi

# ── 4. The version gate ──────────────────────────────────────────────────
say '4/4  app_min_version — the "update required" gate'
note 'A row in app_settings, not a project setting in the Appwrite console.'
note "Editable from the admin panel's Settings page, or here."
MINVER="${MIN_VERSION:-1.0.0}"
if [ "$APPLY" -eq 1 ]; then
  printf '   Set app_min_version to %s now? [y/N] ' "$MINVER"
  read -r answer
  case "$answer" in
    y|Y|yes|YES)
      # PUT is an upsert and the row id *is* the key, which is what the
      # admin panel does — so this updates rather than adding a second
      # row with the same key.
      out="$(mktemp)"
      code="$(curl -sS -o "$out" -w '%{http_code}' -X PUT \
        "$APPWRITE_ENDPOINT/tablesdb/$DB/tables/app_settings/rows/app_min_version" \
        -H 'content-type: application/json' \
        -H "x-appwrite-project: $APPWRITE_PROJECT_ID" \
        -H "x-appwrite-key: $APPWRITE_API_KEY" \
        -d "{\"data\":{\"key\":\"app_min_version\",\"value\":\"$MINVER\"}}" || echo 000)"
      if [ "$code" = '200' ] || [ "$code" = '201' ]; then
        note "Set to $MINVER."
        note 'Raise it only once the new build is live in the stores: every'
        note 'install older than this value is locked out until it updates.'
      else
        note "Appwrite answered $code:"
        sed -n '1,6p' "$out"
        note "Do it in the panel instead — Settings -> Minimum app version."
      fi
      rm -f "$out"
      ;;
    *) note 'Skipped.' ;;
  esac
else
  note "would offer to set it to $MINVER (MIN_VERSION=x.y.z to change)"
fi

# ── Done ─────────────────────────────────────────────────────────────────
if [ "$APPLY" -eq 1 ]; then
  say 'Done'
  note 'Worth checking, in this order:'
  note ''
  note '1. A report filed BEFORE this deploy and since validated should be'
  note '   visible to an Early Responder, with the response controls. That'
  note '   is what proves step 3 ran — a report you file and approve now'
  note '   passes whether it did or not, because new rows get the right'
  note '   ACL from the Function regardless.'
  note '2. A pending report should not appear for that responder at all.'
  note '3. Moving a response status should succeed rather than 403, which'
  note '   is what proves step 1 created the columns.'
  note ''
  note 'This deploy also takes reach away from live accounts. Ask whoever'
  note 'uses the Early Responder role whether anything looked broken: a'
  note 'deliberate change should not get logged as a bug.'
else
  say 'Nothing was changed'
  note "Re-run with --apply to do it:  $0 --apply"
fi
