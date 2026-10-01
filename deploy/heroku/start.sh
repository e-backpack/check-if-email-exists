#!/bin/ash
# Heroku entrypoint for the Reacher backend.
# - binds to $PORT (Heroku) instead of 8080
# - refuses to start without RCH__HEADER_SECRET (no more open backend)
# - logs the dyno's outbound IP and whether port 25 is reachable, so that
#   `heroku logs | grep reacher-boot` shows the IP after each restart.
set -u

if [ -z "${RCH__HEADER_SECRET:-}" ] && [ "${ALLOW_OPEN_BACKEND:-}" != "1" ]; then
  echo "reacher-boot fatal=missing_RCH__HEADER_SECRET"
  exit 1
fi

export RCH__HTTP_PORT="${PORT:-8080}"
export RCH__BACKEND_NAME="${RCH__BACKEND_NAME:-${HEROKU_APP_NAME:-reacher}}"

(
  ip=$(wget -qO- -T 8 https://api.ipify.org 2>/dev/null || echo unknown)
  if timeout 8 nc -w 6 gmail-smtp-in.l.google.com 25 </dev/null 2>/dev/null | head -c 3 | grep -q 220; then p25=open; else p25=blocked; fi
  echo "reacher-boot app=${RCH__BACKEND_NAME} egress_ip=${ip} port25=${p25} hello=${RCH__HELLO_NAME:-unset} dyno=${DYNO:-local}"
) &

chromedriver >/dev/null 2>&1 &
exec ./reacher_backend
