#!/usr/bin/env bash
# Creates (idempotently) the Heroku apps of the pool and deploys the heroku-pool branch on each.
# Needs: heroku CLI logged in (`heroku login`), git, openssl. Run from the repo root.
# Usage: deploy/heroku/create-apps.sh [~/.config/reacher/pool.env]
set -euo pipefail
CONF="${1:-$HOME/.config/reacher/pool.env}"; source "$CONF"
mkdir -p "$(dirname "$SECRET_FILE")"
if [ ! -s "$SECRET_FILE" ]; then (umask 077; openssl rand -hex 32 > "$SECRET_FILE"); echo "new secret written to $SECRET_FILE"; fi
for app in $APPS; do
  echo "== $app"
  heroku apps:info -a "$app" >/dev/null 2>&1 || heroku apps:create "$app" --stack container --region "$REGION"
  # secret read from file, never echoed
  heroku config:set -a "$app" \
    RCH__HEADER_SECRET="$(cat "$SECRET_FILE")" \
    RCH__HELLO_NAME="$HELLO_NAME" RCH__FROM_EMAIL="$FROM_EMAIL" \
    RCH__BACKEND_NAME="$app" RCH__SMTP_TIMEOUT=45 >/dev/null
  git push "https://git.heroku.com/$app.git" heroku-pool:main
  heroku ps:type web=basic -a "$app" >/dev/null
  heroku ps:scale web=1 -a "$app" >/dev/null
done
echo "done. URLs:"; for app in $APPS; do heroku apps:info -a "$app" --json | python3 -c 'import json,sys; print(json.load(sys.stdin)["app"]["web_url"].rstrip("/"))'; done
