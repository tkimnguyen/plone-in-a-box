# syntax=docker/dockerfile:1
# The official plone/plone-frontend build, plus Volto add-ons and an optional
# theme, chosen with build arguments:
#   PACKAGES  npm packages to install, with versions
#   ADDONS    Volto add-ons to load, in order (a theme add-on goes last)
#   THEME     the theme add-on, if any
ARG VOLTO_VERSION=19
FROM plone/frontend-builder:${VOLTO_VERSION} AS builder
ARG PACKAGES
ARG ADDONS
ARG THEME=""

COPY --chown=node:node pnpm-workspace.yaml /app/
RUN --mount=type=cache,id=pnpm,target=/app/.pnpm-store,uid=1000 <<EOT
    set -e
    ADDONS="${ADDONS}" THEME="${THEME}" node -e '
      const addons = process.env.ADDONS.split(/\s+/).filter(Boolean);
      const theme = process.env.THEME;
      require("fs").writeFileSync("volto.config.js",
        `module.exports = ${JSON.stringify({ addons, theme }, null, 2)};\n`);
    '
    cat volto.config.js
    pnpm add -w ${PACKAGES}
    pnpm build
    rm -rf node_modules
    pnpm install --prod
EOT

FROM plone/frontend-prod-config:${VOLTO_VERSION}
COPY --from=builder /app/ /app/
RUN corepack install
