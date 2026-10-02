#!/bin/bash
# Secret patterns, by vendor. Each is anchored on the vendor's own prefix so
# a hit is a hit, not a guess.
declare -A PAT=(
  [appwrite_key]='standard_[0-9a-f]{64,}'
  [supabase_jwt]='eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9\.[A-Za-z0-9_-]{20,}'
  [supabase_sb]='sb_(secret|publishable)_[A-Za-z0-9_-]{20,}'
  [resend]='re_[A-Za-z0-9]{20,}'
  [onesignal_rest]='os_v2_app_[a-z0-9]{20,}'
  [imagekit_priv]='private_[A-Za-z0-9+/=]{20,}'
  [termii]='TL[A-Za-z0-9]{40,}'
  [generic_pk]='-----BEGIN [A-Z ]*PRIVATE KEY-----'
)
repo="$1"; cd "$repo" || exit 1
for name in "${!PAT[@]}"; do
  hits=$(git rev-list --all | while read -r c; do
    git grep -IhoE "${PAT[$name]}" "$c" -- 2>/dev/null
  done | sort -u)
  n=$(printf '%s' "$hits" | grep -c . )
  if [ "$n" -gt 0 ]; then
    echo "### $name: $n distinct"
    printf '%s\n' "$hits" | while read -r h; do
      [ -z "$h" ] && continue
      echo "    ${h:0:14}…${h: -4}  (len ${#h})"
    done
  fi
done
