#!/usr/bin/env bash
# Rotates the outbound IP of every app of the pool, ONE APP AT A TIME (the others keep serving;
# the actors fail over automatically). Uses the Heroku Platform API only (curl + python3), so it
# runs anywhere (mac mini launchd, GitHub Actions) with HEROKU_API_KEY set
# (`heroku authorizations:create -d reacher-rotate` gives a long-lived token).
#
# Per app:  1. read the current egress IP (logged by start.sh at boot: "reacher-boot ... egress_ip=")
#           2. restart the dyno (DELETE /apps/:app/dynos)          -> wait for a new boot line
#           3. if the IP did not change: scale web=0, wait, web=1   -> wait for a new boot line
#           4. wait until /version answers before moving to the next app
# Usage: HEROKU_API_KEY=... deploy/heroku/rotate.sh [~/.config/reacher/pool.env]
set -euo pipefail
CONF="${1:-$HOME/.config/reacher/pool.env}"; source "$CONF"
: "${HEROKU_API_KEY:?HEROKU_API_KEY missing}"
API=https://api.heroku.com
H=(-H "Accept: application/vnd.heroku+json; version=3" -H "Authorization: Bearer $HEROKU_API_KEY" -H "Content-Type: application/json")
log() { echo "$(date -u +%FT%TZ) $*"; }

boot_line() { # last reacher-boot line of the app (from the last 1500 log lines)
  local url; url=$(curl -s "${H[@]}" -X POST "$API/apps/$1/log-sessions" -d '{"lines":1500,"source":"app"}' | python3 -c 'import json,sys; print(json.load(sys.stdin)["logplex_url"])')
  curl -s -m 20 "$url" | grep 'reacher-boot' | tail -1 || true
}
ip_of() { sed -n 's/.*egress_ip=\([^ ]*\).*/\1/p' <<<"$1"; }
wait_new_boot() { # app previous-line
  for _ in $(seq 1 40); do sleep 6; local l; l=$(boot_line "$1"); if [ -n "$l" ] && [ "$l" != "$2" ]; then echo "$l"; return 0; fi; done
  return 1
}
web_url() { curl -s "${H[@]}" "$API/apps/$1" | python3 -c 'import json,sys; print(json.load(sys.stdin)["web_url"].rstrip("/"))'; }
wait_up() { for _ in $(seq 1 30); do curl -sf -m 5 "$1/version" >/dev/null && return 0; sleep 4; done; return 1; }
scale() { curl -s "${H[@]}" -X PATCH "$API/apps/$1/formation/web" -d "{\"quantity\":$2}" >/dev/null; }

status=0
for app in $APPS; do
  before=$(boot_line "$app"); old=$(ip_of "$before")
  log "$app current egress_ip=${old:-unknown}"
  curl -s "${H[@]}" -X DELETE "$API/apps/$app/dynos" >/dev/null
  after=$(wait_new_boot "$app" "$before" || true); new=$(ip_of "$after")
  log "$app after restart egress_ip=${new:-unknown} ($(sed -n 's/.*port25=\([^ ]*\).*/port25=\1/p' <<<"$after"))"
  if [ -z "$new" ] || [ "$new" = "$old" ]; then
    log "$app same IP after restart -> scale 0 / 1"
    scale "$app" 0; sleep 20; scale "$app" 1
    after2=$(wait_new_boot "$app" "$after" || true); new=$(ip_of "$after2")
    log "$app after scale 0/1 egress_ip=${new:-unknown}"
    [ -n "$new" ] && [ "$new" != "$old" ] || { log "$app WARNING: IP unchanged"; status=1; }
  fi
  wait_up "$(web_url "$app")" && log "$app up" || { log "$app NOT answering /version"; status=2; }
done
exit $status
