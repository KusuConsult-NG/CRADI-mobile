#!/usr/bin/env bash
#
# Assemble the mobile app and the admin web app into one repository and push
# it to cradiapps/ewer.
#
#   ./ship-to-ewer.sh            assemble and show what would be pushed
#   ./ship-to-ewer.sh --push     assemble, commit and push the branch
#
# The two apps keep their own directories:
#
#   mobile/   the Flutter app, its Appwrite Functions (functions/cradi),
#             the deployment toolchain (infra/appwrite) and the Supabase
#             migration pipeline
#   web/      the Next.js admin panel
#
# Only files git tracks are copied, so env.json, android/key.properties,
# *.jks, node_modules and build output are left behind by construction
# rather than by an ignore list that has to be kept correct.
#
set -euo pipefail

MOBILE="${MOBILE:-$HOME/CRADI-mobile}"
WEB="${WEB:-$HOME/CRADI-Mobile-Admin}"
REMOTE="${REMOTE:-https://github.com/cradiapps/ewer.git}"
BRANCH="${BRANCH:-ship/monorepo}"
PUSH=0
[ "${1:-}" = "--push" ] && PUSH=1

# Resolved to an absolute path **before** anything cds, because this
# script cds into the clone and then reads its own `root/` directory. With
# `$(dirname "$0")` evaluated after that cd, a relative invocation —
# `bash tools/ship/ship-to-ewer.sh` — looked for `root/` inside the clone
# and died halfway, with the tree already assembled. Only an absolute
# invocation worked, which is not a difference anybody should have to know.
HERE="$(cd "$(dirname "$0")" && pwd)"

say() { printf '\n\033[1m%s\033[0m\n' "$*"; }
die() { printf '\n\033[31merror:\033[0m %s\n' "$*" >&2; exit 1; }

# ── 1. Check the sources ─────────────────────────────────────────────────
for d in "$MOBILE" "$WEB"; do
  [ -d "$d/.git" ] || die "not a git checkout: $d
  Set MOBILE=/path/to/CRADI-mobile and WEB=/path/to/CRADI-Mobile-Admin."
  if [ -n "$(git -C "$d" status --porcelain)" ]; then
    die "$d has uncommitted changes.
  Only committed files are copied, so commit or stash them first —
  otherwise what you ship is not what you are looking at."
  fi
done

say "Sources"
printf '  mobile  %s  %s\n' "$(git -C "$MOBILE" rev-parse --short HEAD)" "$MOBILE"
printf '  web     %s  %s\n' "$(git -C "$WEB" rev-parse --short HEAD)" "$WEB"

# ── 2. Get the target repository ─────────────────────────────────────────
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
say "Cloning $REMOTE"
# git's own output is kept. Discarding it hid the two failures that
# actually happen here — a credential prompt, which looks like a hang, and
# a refusal, which looks like nothing at all. GIT_TERMINAL_PROMPT=0 turns
# the first into an error instead of a wait.
GIT_TERMINAL_PROMPT=0 git clone "$REMOTE" "$WORK/ewer" \
  || die "could not clone $REMOTE

  The reason is in git's output just above. The usual ones:
    'Authentication failed' / 'could not read Username'
        git is not signed in for this remote. Either use the GitHub CLI
        (gh auth login) or switch REMOTE to SSH:
          REMOTE=git@github.com:cradiapps/ewer.git ./ship-to-ewer.sh
    'Repository not found'
        the account you are signed in as cannot see cradiapps/ewer."
cd "$WORK/ewer"
DEFAULT_BRANCH="$(git symbolic-ref --short HEAD)"

# An *orphan* branch, so the deliverable starts from one commit with no
# inherited history. Two reasons. The repository already holds a partial
# copy whose layout does not match this one, so there is nothing to merge
# with. And the source repositories' commit messages carry contributor
# trailers that are not wanted here — a branch on top of them would keep
# every one.
git checkout --quiet --orphan "$BRANCH"
git rm -rf --quiet . >/dev/null 2>&1 || true
find . -mindepth 1 -maxdepth 1 ! -name .git -exec rm -rf {} +

# ── 3. Lay the two apps out ──────────────────────────────────────────────
say "Copying tracked files"
mkdir -p mobile web
git -C "$MOBILE" archive HEAD | tar -x -C mobile
git -C "$WEB" archive HEAD | tar -x -C web
# This directory builds the deliverable; it is not part of it. Two
# reasons, and the second is the one that forced the matter: the client
# has no use for the script that overwrites their repository, and
# `scrub.py` carries every tool and vendor name in its own pattern — so
# shipping it makes the scrub check fail on the scrubber. The check
# caught that itself the first time this ran from `main`.
rm -rf mobile/tools/ship
printf '  mobile  %s files\n' "$(find mobile -type f | wc -l | tr -d ' ')"
printf '  web     %s files\n' "$(find web -type f | wc -l | tr -d ' ')"

# ── 4. Re-root the two workflows ─────────────────────────────────────────
#
# Each workflow was written for a repository root that is now one level
# down. Two kinds of path need two different fixes, and conflating them is
# the usual way this goes wrong:
#
#   * `run:` steps are shell, so one job-level `defaults.run.working-
#     directory` moves all of them at once.
#   * an action's inputs (`path:`, `file:`, `cache-dependency-path:`) are
#     read by the action, not the shell, and ignore working-directory
#     completely. Each has to be rewritten.
#
say "Re-rooting the CI workflows"
mkdir -p .github/workflows
cat > "$WORK/rewrite.py" <<'PYEOF'
import re, sys
PREFIX = sys.argv[2]
src = open(sys.argv[1]).read()

text = re.sub(r'(working-directory:\s+)([^\s#]+)',
              lambda m: m.group(1) + (PREFIX if m.group(2) in ('.', './')
                                      else f'{PREFIX}/{m.group(2)}'), src)
for key in ('cache-dependency-path', 'file', 'path'):
    text = re.sub(r'(\n\s+' + key + r':\s+)([^\s#$][^\s#]*)',
                  lambda m: m.group(1) + f'{PREFIX}/{m.group(2)}', text)

# `cache: npm` with no `cache-dependency-path` looks for a lock file in the
# repository root. That was right when the project *was* the root; it is not
# now, and there is no key to prefix because the lookup was implicit. Add one.
out2, lines2 = [], text.split('\n')
for n, line in enumerate(lines2):
    out2.append(line)
    m = re.match(r'^(\s+)cache:\s*(npm|yarn|pnpm)\s*$', line)
    if not m:
        continue
    indent = m.group(1)
    siblings = []
    for later in lines2[n + 1:]:
        if later.strip() and not later.startswith(indent):
            break
        siblings.append(later)
    if any(re.match(r'^' + indent + r'cache-dependency-path:', s2) for s2 in siblings):
        continue
    lock = {'npm': 'package-lock.json', 'yarn': 'yarn.lock',
            'pnpm': 'pnpm-lock.yaml'}[m.group(2)]
    out2.append(f'{indent}cache-dependency-path: {PREFIX}/{lock}')
text = '\n'.join(out2)

lines, out, i = text.split('\n'), [], 0
while i < len(lines):
    line = lines[i]
    if re.match(r'^  [A-Za-z0-9_-]+:\s*$', line):
        j, body, has_defaults = i + 1, [], False
        while j < len(lines) and (lines[j].startswith('    ') or not lines[j].strip()):
            if re.match(r'^    defaults:\s*$', lines[j]):
                has_defaults = True
            body.append(lines[j]); j += 1
        out.append(line)
        if not has_defaults:
            k = next((n for n, b in enumerate(body)
                      if re.match(r'^    runs-on:', b)), None)
            if k is not None:
                body[k + 1:k + 1] = ['    defaults:', '      run:',
                                     f'        working-directory: {PREFIX}']
        out.extend(body); i = j; continue
    out.append(line); i += 1
sys.stdout.write('\n'.join(out))
PYEOF

python3 "$WORK/rewrite.py" mobile/.github/workflows/ci.yml mobile \
  | sed '1s/^name: CI$/name: Mobile CI/' > .github/workflows/mobile.yml
python3 "$WORK/rewrite.py" web/.github/workflows/ci.yml web \
  | sed '1s/^name: CI$/name: Web CI/' > .github/workflows/web.yml
rm -rf mobile/.github web/.github

python3 - <<'PYEOF'
import sys
try:
    import yaml
except ImportError:
    print('  (PyYAML not installed — skipping the parse check)')
    sys.exit(0)
for f in ('.github/workflows/mobile.yml', '.github/workflows/web.yml'):
    d = yaml.safe_load(open(f))
    print(f'  {f}  {len(d["jobs"])} jobs, parses OK')
PYEOF

# ── 5. Root-level files ──────────────────────────────────────────────────
say "Writing the root files"
for f in README.md docs/IMPLEMENTATION.md scripts/deploy.sh; do
  src="$HERE/root/$f"
  [ -f "$src" ] || die "missing $src — keep ship-to-ewer.sh next to its root/ directory."
  mkdir -p "$(dirname "$f")"
  cp "$src" "$f"
  printf '  %s\n' "$f"
done
chmod +x scripts/deploy.sh

# ── 6. Scrub tooling references, then prove none are left ────────────────
say "Scrubbing tooling references"
SCRUB="$HERE/scrub.py"
[ -f "$SCRUB" ] || die "missing $SCRUB — keep it next to ship-to-ewer.sh."
# Text files only: a PNG whose bytes happen to spell one of these is not a
# reference, and rewriting it would corrupt the image.
#
# The list goes to a file rather than an array: macOS ships bash 3.2, which
# has no `mapfile`, and expanding an empty array under `set -u` there is an
# error rather than nothing.
# -print0/-0: two tracked assets have spaces in their names, and plain
# xargs would split each into two arguments that match no file.
find . -path ./.git -prune -o -type f -print0 \
  | xargs -0 grep -Il '' 2>/dev/null | sort -u > "$WORK/text-files"
TEXT_COUNT="$(wc -l < "$WORK/text-files" | tr -d ' ')"
python3 "$SCRUB" --from-file "$WORK/text-files"

say "Checking nothing was missed"
if ! python3 "$SCRUB" --check --from-file "$WORK/text-files"; then
  die "the tree still names a tool or vendor — see the lines above.
  Add a rewrite to scrub.py, or edit the source repository, then re-run."
fi
printf '  clean: %s text files, no tool or vendor names\n' "$TEXT_COUNT"

# ── 7. Commit ────────────────────────────────────────────────────────────
git add -A
if git diff --cached --quiet; then
  say "Nothing changed — the repository already matches the sources."
  exit 0
fi

MOBILE_SHA="$(git -C "$MOBILE" rev-parse --short HEAD)"
WEB_SHA="$(git -C "$WEB" rev-parse --short HEAD)"
git -c user.email="${GIT_AUTHOR_EMAIL:-$(git config user.email)}" \
    -c user.name="${GIT_AUTHOR_NAME:-$(git config user.name)}" \
    commit --quiet -m "Ship the mobile app and admin panel as one repository

mobile/  Flutter app, Appwrite Functions, deployment toolchain  ($MOBILE_SHA)
web/     Next.js admin panel                                    ($WEB_SHA)

Both workflows are re-rooted under their directory: each job carries a
defaults.run.working-directory, and the action inputs that working-directory
does not reach (cache-dependency-path, upload-artifact path, codecov file)
are prefixed separately.

Only tracked files are copied, so env.json, android/key.properties, the
signing keystore, node_modules and build output are not included.

This branch starts from no parent commit, so none of either repository's
history comes with it."

say "Assembled $(git rev-parse --short HEAD) on $BRANCH"
# `sed -n`, not `head`: head closes the pipe as soon as it has its lines,
# git dies on SIGPIPE, and `set -o pipefail` turns that into a failure that
# ends the script — silently, because SIGPIPE prints nothing. sed reads to
# the end instead. A commit of 700 files hits this; a commit of 11 does not,
# which is why it survived testing.
git show --stat --oneline HEAD | sed -n '1,20p'
printf '\n  %s files total\n' "$(git ls-files | wc -l | tr -d ' ')"

# ── 8. Push ──────────────────────────────────────────────────────────────
if [ "$PUSH" -eq 1 ]; then
  say "Pushing"
  for n in 1 2 3 4; do
    git push -u origin "$BRANCH" && break
    printf '  push failed, retrying in %ss\n' "$((2 ** n))"; sleep "$((2 ** n))"
  done
  SLUG="$(printf '%s' "$REMOTE" | sed -E 's#.*github\.com[:/]##; s#\.git$##')"
  printf '\n  Open a pull request:\n  https://github.com/%s/compare/%s...%s?expand=1\n' \
    "$SLUG" "$DEFAULT_BRANCH" "$BRANCH"
else
  say "Not pushed. Re-run with --push to push $BRANCH to $REMOTE."
fi
