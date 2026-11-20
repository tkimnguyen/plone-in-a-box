# Custom frontend image (prototype)

The official `plone/plone-frontend` build with Volto add-ons added, for the
"custom images" item in TODO.md. `.github/workflows/frontend-image.yml` builds
it and pushes `ghcr.io/tkimnguyen/plone-in-a-box-frontend`.

To use it on a box, set the frontend image in `/opt/plone/docker-compose.yml`,
then `docker compose --project-directory /opt/plone up -d frontend`.

The add-ons are listed twice: as npm packages in the Dockerfile's
`VOLTO_ADDONS`, and as Volto add-ons in `volto.config.js`.
