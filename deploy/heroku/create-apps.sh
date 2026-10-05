#!/usr/bin/env bash
# Creates (idempotently) the Heroku apps of the pool and deploys the heroku-pool branch on each.
# Needs: heroku CLI logged in (`heroku login`), git, openssl. Run from the repo root.
# No local Docker needed: the image is built by Heroku from heroku.yml (stack "container") on `git push`.
# Usage: deploy/heroku/create-apps.sh [~/.config/reacher/pool.env]
#   TEAM (pool.env)        Heroku team owning the apps (e.g. pnda); empty = personal account
#   REGION (env or pool.env, default us)  MUST stay "us": outbound port 25 is blocked in the eu
#                          region (tested 05/10/2026: gmail-smtp-in:25 answers 220 from us, times out from eu).
#                          An environment REGION=... overrides pool.env. Region is fixed at app creation.
#   HELLO_NAME / FROM_EMAIL empty = temporary identity derived from each app's herokuapp.com host
set -euo pipefail
CONF="${1:-$HOME/.config/reacher/pool.env}"; ENV_REGION="${REGION:-}"; source "$CONF"
TEAM="${TEAM:-}"; REGION="${ENV_REGION:-${REGION:-us}}"
[ "$REGION" = us ] || echo "WARNING: region $REGION, outbound port 25 is blocked outside us (SMTP checks will time out)" >&2
mkdir -p "$(dirname "$SECRET_FILE")"
if [ ! -s "$SECRET_FILE" ]; then (umask 077; openssl rand -hex 32 > "$SECRET_FILE"); echo "new secret written to $SECRET_FILE"; fi
for app in $APPS; do
  echo "== $app"
  if heroku apps:info -a "$app" >/dev/null 2>&1; then
    r=$(heroku apps:info -a "$app" --json | python3 -c 'import json,sys; print(json.load(sys.stdin)["app"]["region"]["name"])')
    [ "$r" = "$REGION" ] || echo "WARNING: $app already exists in region $r (expected $REGION); region cannot be changed, recreate the app" >&2
  else
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
