#!/bin/bash
#
# Plone in a Box(TM) for DigitalOcean, without Terraform.
#
# When creating an Ubuntu 24.04 Droplet, open Advanced Options, check
# "Add initialization scripts", paste this whole file, and edit the settings
# below. Keep each value inside the single quotes (a value can't contain a
# single quote itself).
#
# Open the Droplet's address a minute or two after it boots to watch the setup
# progress page, which turns into your Plone site when it's ready (about
# 10 minutes). Log in as "admin".

# Plone admin password, at least 12 characters. Leave empty to have one
# generated; then read it over SSH with: cat /root/plone-credentials.txt
export ADMIN_PASSWORD=''

# Domain name for the site, optional. DNS must already point at the Droplet
# to get HTTPS, and LETSENCRYPT_EMAIL is required with it.
export DOMAIN=''
export LETSENCRYPT_EMAIL=''

# Site time zone, for example America/Chicago.
export SITE_TIMEZONE='UTC'

# Plone backend and Volto frontend image tags.
export PLONE_VERSION='6.1'
export VOLTO_VERSION='18'

# --- No need to edit below this line -----------------------------------------

# The Plone in a Box release whose provisioning script is downloaded and run.
PIAB_RELEASE='2.2'
SCRIPT_URL="https://raw.githubusercontent.com/tkimnguyen/plone-in-a-box/${PIAB_RELEASE}/src/StackScript"

set -uo pipefail
SCRIPT=$(mktemp)
if ! curl --fail --silent --show-error --location --retry 10 --retry-delay 5 --retry-all-errors \
    --output "$SCRIPT" "$SCRIPT_URL"; then
  echo "[plone-in-a-box] Could not download $SCRIPT_URL" | tee -a /var/log/plone-in-a-box.log >&2
  exit 1
fi
exec bash "$SCRIPT"
