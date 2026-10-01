#!/usr/bin/env bash
# Validates one or more Reacher URLs: version, refusal without secret, safe / catch-all / invalid
# answers, and SMTP identity. Usage: deploy/heroku/validate.sh https://a.herokuapp.com [https://b...]
# Reads the secret from $SECRET_FILE (default ~/.config/reacher/secret), never prints it.
set -uo pipefail
SECRET_FILE="${SECRET_FILE:-$HOME/.config/reacher/secret}"; S="$(cat "$SECRET_FILE")"
fail=0
check() { # url email expected-python-expr label
  curl -s -m 90 -X POST "$1/v0/check_email" -H 'content-type: application/json' -H "x-reacher-secret: $S" \
    -d "{\"to_email\":\"$2\"}" | python3 -c "
import json,sys
d=json.load(sys.stdin); s=d.get('smtp',{}); vm=d.get('debug',{}).get('smtp',{}).get('verif_method',{}).get('verif_method',{})
ok=$3
print(('  OK  ' if ok else '  FAIL'), '$4', 'is_reachable=',d.get('is_reachable'),'catch_all=',s.get('is_catch_all'),'deliverable=',s.get('is_deliverable'),'hello=',vm.get('hello_name'),'from=',vm.get('from_email'))
sys.exit(0 if ok else 1)" || fail=1
}
for u in "$@"; do
  u="${u%/}"; echo "== $u"
  echo "  version: $(curl -s -m 15 "$u/version")"
  code=$(curl -s -o /dev/null -w '%{http_code}' -m 30 -X POST "$u/v0/check_email" -H 'content-type: application/json' -d '{"to_email":"rand@sparktoro.com"}')
  if [ "$code" = 400 ] || [ "$code" = 401 ]; then echo "  OK   no secret -> $code (refused)"; else echo "  FAIL no secret -> $code (should be refused)"; fail=1; fi
  check "$u" rand@sparktoro.com "d.get('is_reachable')=='safe' and s.get('is_deliverable') is True" safe
  check "$u" qz7x9k2m4p@intercom.io "s.get('is_catch_all') is True" catch-all
  check "$u" qz7x9k2m4p@hubspot.com "d.get('is_reachable')=='invalid'" invalid
done
exit $fail
