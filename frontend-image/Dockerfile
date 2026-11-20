# syntax=docker/dockerfile:1
# Prototype: the official plone/plone-frontend:19 build, plus Volto add-ons.
ARG VOLTO_VERSION=19
FROM plone/frontend-builder:${VOLTO_VERSION} AS builder
ARG VOLTO_ADDONS="volto-form-block@3.20.0"

COPY --chown=node:node pnpm-workspace.yaml volto.config.js /app/
RUN --mount=type=cache,id=pnpm,target=/app/.pnpm-store,uid=1000 <<EOT
    set -e
    pnpm add -w ${VOLTO_ADDONS}
    pnpm build
    rm -rf node_modules
    pnpm install --prod
EOT

FROM plone/frontend-prod-config:${VOLTO_VERSION}
COPY --from=builder /app/ /app/
RUN corepack install
