#!/usr/bin/env bash
# TEST HARNESS ONLY — copies a hand-picked set of screenshots out of
# web_smoke/screenshots/ into web_smoke/highlights/, renamed in reading order.
#
# The passes have several hundred shots between them; this is the short set
# that shows the app working end to end. Run it after ./web_smoke/run.sh.
set -euo pipefail
cd "$(dirname "$0")/.."

SRC=web_smoke/screenshots
OUT=web_smoke/highlights
rm -rf "$OUT"
mkdir -p "$OUT"

copy() { # copy <source-relative-to-SRC> <name>
    if [ ! -f "$SRC/$1" ]; then
        echo "missing: $SRC/$1" >&2
        exit 1
    fi
    cp "$SRC/$1" "$OUT/$2.png"
}

copy signed-out/007-login-empty.png                      01-login
copy role-ewm/002-dashboard.png                          02-dashboard
copy role-user/028-report-1-hazard-selected-Flooding.png 03-report-1-hazard
copy role-user/030-report-2-severity-set-Flooding.png    04-report-2-severity
copy role-user/032-report-3-location-filled-Flooding.png 05-report-3-location
copy role-user/034-report-4-details-filled-Flooding.png  06-report-4-details
copy role-user/035-report-4-details-Flooding.png         07-report-5-review
copy role-user/037-report-5-submitted-Flooding.png       08-report-6-submitted
copy role-user/004-my-reports.png                        09-my-reports
copy role-user/016-reports-status.png                    10-reports-status
copy role-ewv/017-verification-list.png                  11-verification-list
copy focus/007-verification-vote.png                     12-verification-vote-cast
copy role-user/006-alerts.png                            13-alerts
copy role-user/007-knowledge-base.png                    14-knowledge-base
copy role-user/059-sos-sheet.png                         15-contacts-sos
copy role-admin/020-admin.png                            16-admin-portal
copy role-admin/040-admin-users-row-menu-open.png        17-admin-users-menu
copy role-admin/042-admin-knowledge-row-menu-open.png    18-admin-knowledge-menu
copy languages/019-Hausa-dashboard.png                   19-hausa-dashboard
copy small-viewport-320x640/001-dashboard.png            20-dashboard-320px

echo "$(ls "$OUT" | wc -l) screenshots in $OUT"
