#!/usr/bin/env bash
# Brings the local stack to a state the tests can use, from scratch or
# after a container restart. Idempotent.
#
#   source infra/appwrite/local/up.sh
set -euo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# The hosts entry does not survive a container rebuild, and without it
# every call gets the console's HTML instead of the API. See README.
grep -q "appwrite.local" /etc/hosts || echo "127.0.0.1 appwrite.local" >> /etc/hosts

docker info >/dev/null 2>&1 || { (dockerd >/tmp/dockerd.log 2>&1 &); sleep 15; }
docker network create runtimes19 >/dev/null 2>&1 || true
docker compose -f "$here/docker-compose.yml" up -d >/dev/null
until curl -sS -o /dev/null "http://appwrite.local:8090/v1/health" 2>/dev/null; do sleep 2; done
echo "stack up on http://appwrite.local:8090/v1"
