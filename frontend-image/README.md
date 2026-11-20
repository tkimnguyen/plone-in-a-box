# Custom frontend image (prototype)

The official `plone/plone-frontend` build with Volto add-ons added, for the
"custom images" item in TODO.md. `.github/workflows/frontend-image.yml` builds
them and pushes `ghcr.io/tkimnguyen/plone-in-a-box-frontend:<tag>`.

To use it on a box, set the frontend image in `/opt/plone/docker-compose.yml`,
then `docker compose --project-directory /opt/plone up -d frontend`.

Each image is one entry in the workflow's matrix, with three build arguments:
`PACKAGES` (npm packages to install, with versions), `ADDONS` (Volto add-ons to
load, in order; a theme add-on goes last) and `THEME` (the theme add-on, if any).
The Dockerfile writes `volto.config.js` from them.
