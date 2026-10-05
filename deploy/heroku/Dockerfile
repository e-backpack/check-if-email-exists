# Thin wrapper around the official Reacher image (no Rust build on Heroku).
# Pin the version: bump it deliberately, then redeploy the apps one at a time.
FROM reacherhq/backend:v0.11.7

USER root
# Heroku (heroku.yml) uses the Dockerfile's directory as build context, hence the bare path.
# Local build: docker build -f deploy/heroku/Dockerfile deploy/heroku
COPY start.sh /home/reacher/start.sh
RUN chmod 755 /home/reacher/start.sh && chown chrome:chrome /home/reacher/start.sh
USER chrome

# Defaults; anything set with `heroku config:set` overrides them.
ENV RUST_LOG=reacher=info \
    RCH__HTTP_HOST=0.0.0.0 \
    RCH__WORKER__ENABLE=false \
    RCH__SMTP_TIMEOUT=45

CMD ["/home/reacher/start.sh"]
