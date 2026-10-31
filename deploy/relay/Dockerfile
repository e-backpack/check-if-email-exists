# Stable entry point of the Reacher pool: keeps the URL and the secret clients already use.
FROM node:22-alpine
WORKDIR /app
COPY relay.mjs .
USER node
CMD ["node", "relay.mjs"]
