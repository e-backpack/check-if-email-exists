#!/usr/bin/env bash
# Creates (idempotently) the Heroku apps of the pool and deploys the heroku-pool branch on each.
# Needs: heroku CLI logged in (`heroku login`), git, openssl. Run from the repo root.
# No local Docker needed: the image is built by Heroku from heroku.yml (stack "container") on `git push`.
# Usage: deploy/heroku/create-apps.sh [~/.config/reacher/pool.env]
#   TEAM (pool.env)        Heroku team owning the apps (e.g. pnda); empty = personal account
#   HELLO_NAME / FROM_EMAIL empty = temporary identity derived from each app's herokuapp.com host
set -euo pipefail
CONF="${1:-$HOME/.config/reacher/pool.env}"; source "$CONF"
TEAM="${TEAM:-}"; REGION="${REGION:-eu}"
mkdir -p "$(dirname "$SECRET_FILE")"
if [ ! -s "$SECRET_FILE" ]; then (umask 077; openssl rand -hex 32 > "$SECRET_FILE"); echo "new secret written to $SECRET_FILE"; fi
for app in $APPS; do
  echo "== $app"
  if ! heroku apps:info -a "$app" >/dev/null 2>&1; then
    heroku apps:create "$app" --stack container --region "$REGION" ${TEAM:+--team "$TEAM"}
  fi
  heroku stack:set container -a "$app" >/dev/null
  host=$(heroku apps:info -a "$app" --json | python3 -c 'import json,sys,urllib.parse; print(urllib.parse.urlparse(json.load(sys.stdin)["app"]["web_url"]).hostname)')
  hello="${HELLO_NAME:-$host}"; from="${FROM_EMAIL:-verify@$host}"
  # secret read from file, never echoed
  heroku config:set -a "$app" \
    RCH__HEADER_SECRET="$(cat "$SECRET_FILE")" \
    RCH__HELLO_NAME="$hello" RCH__FROM_EMAIL="$from" \
    RCH__BACKEND_NAME="$app" RCH__SMTP_TIMEOUT=45 >/dev/null
  git push "https://git.heroku.com/$app.git" heroku-pool:main
  heroku ps:type web=basic -a "$app" >/dev/null
  heroku ps:scale web=1 -a "$app" >/dev/null
done
echo "done. URLs:"; for app in $APPS; do heroku apps:info -a "$app" --json | python3 -c 'import json,sys; print(json.load(sys.stdin)["app"]["web_url"].rstrip("/"))'; done
