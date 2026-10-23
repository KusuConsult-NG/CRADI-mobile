#!/usr/bin/env python3
"""Remove references to the tooling a contributor happened to use.

These are all in prose about the *development* environment, never in the
product: which hosts a sandboxed CI runner cannot reach, and which branch
some work landed on. The operational fact in each is worth keeping, so
each is reworded rather than deleted.

Run with the assembled tree as the working directory. Exits non-zero if a
reference it does not know how to rewrite is still present, so a new one
arriving in a source repository fails the build instead of shipping.
"""
import re
import sys

REWRITES = [
    # docs/CLOUD-VERIFICATION.md — how to run the Cloud checks from CI.
    (r'> To run it from a [A-Za-z ]*Code session instead, the environment\'s\n'
     r'> \*\*Network access\*\* setting needs `fra\.cloud\.appwrite\.io` allowed, and\n'
     r'> the six `APPWRITE_\*`/`TERMII_\*` variables below have to be in the\n'
     r'> environment\'s settings — a session has none of them today\.',
     '> To run it from a hosted CI environment instead, that environment\n'
     '> must allow outbound access to `fra.cloud.appwrite.io`, and the six\n'
     '> `APPWRITE_*`/`TERMII_*` variables below have to be set there.'),

    # docs/HANDOFF.md — the branch the work landed on is not interesting.
    (r'Both repositories: branch `[^`]+`, merged to\n`main` and pushed\.',
     'Both repositories: merged to `main` and pushed.'),

    # docs/HANDOFF.md — the outbound allow-list the Cloud sequence needs.
    (r'So a [A-Za-z ]*cloud session cannot reach Appwrite Cloud \*or\*\n'
     r'Termii\. Both hosts need adding under \*\*Network access → Custom →\n'
     r'Allowed domains\*\* \(keeping the default package-manager list\) in the\n'
     r'environment\'s settings — the cloud environment menu in the session\'s\n'
     r'title bar, then Edit\. Steps:\n'
     r'<https://[^>]+>',
     'So a sandboxed CI environment cannot reach Appwrite Cloud *or*\n'
     'Termii. Both hosts have to be added to that environment\'s outbound\n'
     'allow-list, alongside the default package-manager domains.'),
]

# Tool and vendor names only. Not the bare letters "AI", which occur inside
# email, fail, main, available, detail and dozens of identifiers.
FORBIDDEN = re.compile(
    r'claude|anthropic|copilot|chatgpt|openai|\bgpt-|co-authored-by|'
    r'\bAI[- ](?:assistant|generated|written)', re.I)

args = sys.argv[1:]
check_only = False
if args and args[0] == '--check':
    check_only, args = True, args[1:]
# A list in a file rather than on the command line: the tree has thousands
# of text files, which is past what a single argv can hold, and splitting
# it across several xargs invocations would lose the exit code that makes
# --check a usable guard.
if len(args) == 2 and args[0] == '--from-file':
    args = [l for l in open(args[1], encoding='utf-8').read().split('\n') if l]

if check_only:
    found = 0
    for path in args:
        try:
            text = open(path, encoding='utf-8').read()
        except (UnicodeDecodeError, OSError):
            continue
        for n, line in enumerate(text.split('\n'), 1):
            if FORBIDDEN.search(line):
                print(f'  {path}:{n}: {line.strip()[:100]}')
                found += 1
    sys.exit(1 if found else 0)

changed = []
for path in args:
    try:
        before = open(path, encoding='utf-8').read()
    except (UnicodeDecodeError, OSError):
        continue
    after = before
    for pattern, replacement in REWRITES:
        after = re.sub(pattern, replacement, after)
    if after != before:
        open(path, 'w', encoding='utf-8').write(after)
        changed.append(path)

for path in changed:
    print(f'  rewritten  {path}')
if not changed:
    print('  nothing to rewrite')
