# Reacher on Heroku: pool of apps + IP rotation

Branch `heroku-pool` of e-backpack/check-if-email-exists. It does not touch the Rust code: the image is
the official `reacherhq/backend:v0.11.7` with a small entrypoint (`start.sh`) that

- binds to `$PORT`,
- refuses to start without `RCH__HEADER_SECRET` (clients must send `x-reacher-secret`; a missing or
  wrong header gets **400** `Invalid/Missing request header "x-reacher-secret"`),
- logs `reacher-boot app=… egress_ip=… port25=open|blocked` at every boot (used by `rotate.sh`).

| file | role |
|---|---|
| `heroku.yml`, `deploy/heroku/Dockerfile`, `start.sh` | container build for Heroku (`--stack container`) |
| `pool.env.example` | app names, region, HELO / MAIL FROM identity, secret file path |
| `create-apps.sh` | creates / updates every app, sets config, pushes this branch, `web=1` on Basic dynos |
| `validate.sh` | version, refusal without secret, safe / catch-all / invalid answers, HELO / FROM |
| `rotate.sh` | restart one app at a time, check the IP changed, else scale 0 → 1 (Platform API) |
| `rotate.github-workflow.yml` | cron template (every 6 h) |

Full runbook (costs, risks, cut-over order): `~/Documents/apify-actors/REACHER-INFRA.md` on the owner's Mac.
