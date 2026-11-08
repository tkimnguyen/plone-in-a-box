#!/usr/bin/env bash
#
# Deploy a throwaway Plone in a Box test server on Linode or DigitalOcean,
# run the checks from RELEASING.md against it, and delete it again.
#
# Usage:
#   scripts/test-deploy.sh linode|digitalocean [options]
#   scripts/test-deploy.sh list|cleanup linode|digitalocean
#
# Options:
#   --ref REF              branch, tag or commit to test (default: the current
#                          branch); it must be pushed to origin
#   --generated-password   deploy without an admin password, so setup generates
#                          one (default: set a random one when deploying)
#   --keep                 don't delete the server at the end (delete it later
#                          with "cleanup")
#
# "list" shows the test servers that exist; "cleanup" deletes all of them.
# Only servers tagged piab-test are ever touched.
#
# Needs: curl, jq, ssh, git, nc. API tokens come from the macOS Keychain
# (services piab-linode-token and piab-do-token) or from LINODE_TOKEN /
# DIGITALOCEAN_TOKEN. The test servers get the SSH key ~/.ssh/piab_test_ed25519
# (or PIAB_TEST_SSH_KEY). Optional: PIAB_TEST_REGION, PIAB_LINODE_FIREWALL_ID.
#
# Linode deploys use the private StackScript "plone-in-a-box-test", which this
# script overwrites with src/StackScript from REF. DigitalOcean deploys paste
# src/user-data.sh from REF as user data, set to download src/StackScript from
# the same commit.

set -euo pipefail

TAG=piab-test
LINODE_STACKSCRIPT_LABEL=plone-in-a-box-test
SSH_KEY="${PIAB_TEST_SSH_KEY:-$HOME/.ssh/piab_test_ed25519}"

PROVIDER="" ACTION=deploy REF="" GENERATED=0 KEEP=0
SERVER_ID="" IP="" FAILURES=0

die() { echo "error: $*" >&2; exit 1; }
say() { printf '[%s] %s\n' "$(date +%H:%M:%S)" "$*"; }
pass() { say "PASS  $*"; }
fail() { say "FAIL  $*"; FAILURES=$((FAILURES + 1)); }
check() { local what=$1; shift; if "$@" >/dev/null 2>&1; then pass "$what"; else fail "$what"; fi; }

usage() { sed -n '3,20p' "$0" | sed 's/^# \{0,1\}//'; exit 2; }

case "${1:-}" in
  linode|digitalocean) PROVIDER=$1 ;;
  list|cleanup) ACTION=$1; PROVIDER=${2:-}; shift ;;
  *) usage ;;
esac
shift
[[ "$PROVIDER" == linode || "$PROVIDER" == digitalocean ]] || usage
while (( $# )); do
  case "$1" in
    --ref) REF=${2:?--ref needs a value}; shift ;;
    --generated-password) GENERATED=1 ;;
    --keep) KEEP=1 ;;
    *) usage ;;
  esac
  shift
done

for tool in curl jq ssh git nc; do
  command -v "$tool" >/dev/null || die "$tool is not installed"
done

# --- API access ---------------------------------------------------------------

keychain_token() {
  command -v security >/dev/null && security find-generic-password -s "$1" -w 2>/dev/null
}
if [[ "$PROVIDER" == linode ]]; then
  TOKEN="${LINODE_TOKEN:-$(keychain_token piab-linode-token || true)}"
  API=https://api.linode.com/v4
else
  TOKEN="${DIGITALOCEAN_TOKEN:-$(keychain_token piab-do-token || true)}"
  API=https://api.digitalocean.com/v2
fi
[[ -n "$TOKEN" ]] || die "no API token for $PROVIDER (see the comments at the top of this script)"

# api METHOD PATH [JSON body] [extra header]: prints the response body, fails on
# an HTTP error. The token goes to curl on stdin, so it isn't in the process list.
api() {
  local method=$1 path=$2 data=${3:-} header=${4:-} out code body
  local args=(-sS -X "$method" -H 'Content-Type: application/json' -w '\n%{http_code}')
  [[ -n "$data" ]] && args+=(--data "$data")
  [[ -n "$header" ]] && args+=(-H "$header")
  out=$(printf 'header = "Authorization: Bearer %s"\n' "$TOKEN" | curl -K - "${args[@]}" "$API$path") \
    || return 1
  code=${out##*$'\n'}
  body=${out%$'\n'*}
  if (( code >= 300 )); then
    echo "$method $path: HTTP $code: $(jq -c '.errors // .message // .' <<<"$body" 2>/dev/null || echo "$body")" >&2
    return 1
  fi
  printf '%s' "$body"
}

list_servers() {
  if [[ "$PROVIDER" == linode ]]; then
    api GET /linode/instances '' "X-Filter: {\"tags\": \"$TAG\"}" \
      | jq -r '.data[] | "\(.id)\t\(.label)\t\(.ipv4[0])\t\(.status)"'
  else
    api GET "/droplets?tag_name=$TAG&per_page=200" \
      | jq -r '.droplets[] | "\(.id)\t\(.name)\t\((.networks.v4[] | select(.type == "public") | .ip_address) // "-")\t\(.status)"'
  fi
}

delete_server() {
  if [[ "$PROVIDER" == linode ]]; then
    api DELETE "/linode/instances/$1" >/dev/null
  else
    api DELETE "/droplets/$1" >/dev/null
  fi
}

if [[ "$ACTION" != deploy ]]; then
  servers=$(list_servers)
  if [[ -z "$servers" ]]; then
    echo "No $PROVIDER servers tagged $TAG."
    exit 0
  fi
  echo "$servers"
  if [[ "$ACTION" == cleanup ]]; then
    while IFS=$'\t' read -r id label _; do
      delete_server "$id" && echo "Deleted $label ($id)"
    done <<<"$servers"
  fi
  exit 0
fi

# --- What to deploy -------------------------------------------------------------

[[ -f "$SSH_KEY" && -f "$SSH_KEY.pub" ]] \
  || die "SSH key $SSH_KEY not found; create it with: ssh-keygen -t ed25519 -f $SSH_KEY -C piab-test -N ''"

cd "$(git rev-parse --show-toplevel)"
REF=${REF:-$(git rev-parse --abbrev-ref HEAD)}
git fetch -q origin
SHA=$(git rev-parse --verify -q "origin/$REF^{commit}" || git rev-parse --verify -q "$REF^{commit}") \
  || die "can't find $REF"
git branch -r --contains "$SHA" 2>/dev/null | grep -q 'origin/' \
  || git ls-remote --tags origin | grep -q "^$SHA" \
  || die "$REF ($SHA) isn't pushed to origin; the server downloads it from GitHub"

WORK=$(mktemp -d "${TMPDIR:-/tmp}/piab-test.XXXXXX")
chmod 700 "$WORK"
NAME="$TAG-$PROVIDER-$(date +%Y%m%d-%H%M%S)"
ADMIN_PASSWORD=""
(( GENERATED )) || ADMIN_PASSWORD=$(openssl rand -base64 24 | tr -dc 'A-Za-z0-9' | cut -c1-20)

say "Testing $REF ($(git rev-parse --short "$SHA")) on $PROVIDER as $NAME"
say "Notes, passwords and logs: $WORK"
{
  echo "ref=$REF sha=$SHA name=$NAME"
  (( GENERATED )) && echo "admin password: generated on the server" || echo "admin password: $ADMIN_PASSWORD"
} > "$WORK/notes.txt"

cleanup_on_exit() {
  local status=$?
  if [[ -n "$SERVER_ID" ]]; then
    if (( KEEP )); then
      say "Kept $NAME ($SERVER_ID) at $IP. Delete it with: $0 cleanup $PROVIDER"
    else
      say "Deleting $NAME"
      delete_server "$SERVER_ID" || say "Couldn't delete $NAME ($SERVER_ID); run: $0 cleanup $PROVIDER"
    fi
  fi
  exit "$status"
}
trap cleanup_on_exit EXIT
trap 'exit 130' INT TERM

# --- Create the server ------------------------------------------------------------

if [[ "$PROVIDER" == linode ]]; then
  REGION=${PIAB_TEST_REGION:-ca-central}
  STACKSCRIPT_ID=$(api GET /linode/stackscripts '' \
      "X-Filter: {\"label\": \"$LINODE_STACKSCRIPT_LABEL\", \"mine\": true}" | jq -r '.data[0].id // empty')
  [[ -n "$STACKSCRIPT_ID" ]] || die "no StackScript named $LINODE_STACKSCRIPT_LABEL in this Linode account"
  say "Updating StackScript $LINODE_STACKSCRIPT_LABEL ($STACKSCRIPT_ID) to src/StackScript from $REF"
  api PUT "/linode/stackscripts/$STACKSCRIPT_ID" "$(git show "$SHA:src/StackScript" | jq -Rs \
      --arg note "Test $REF ($(git rev-parse --short "$SHA"))" '{script: ., rev_note: $note}')" >/dev/null
  ROOT_PASS=$(openssl rand -base64 33 | tr -d '\n')
  body=$(jq -nc --arg region "$REGION" --arg label "$NAME" --arg tag "$TAG" --arg root "$ROOT_PASS" \
      --arg key "$(cat "$SSH_KEY.pub")" --argjson ss "$STACKSCRIPT_ID" --arg pw "$ADMIN_PASSWORD" \
      --arg fw "${PIAB_LINODE_FIREWALL_ID:-}" \
      '{region: $region, type: "g6-nanode-1", image: "linode/ubuntu24.04", label: $label, tags: [$tag],
        root_pass: $root, authorized_keys: [$key], stackscript_id: $ss,
        stackscript_data: {ADMIN_PASSWORD: $pw}, booted: true}
       + (if $fw == "" then {} else {firewall_id: ($fw | tonumber)} end)')
  created=$(api POST /linode/instances "$body")
  SERVER_ID=$(jq -r '.id' <<<"$created")
  IP=$(jq -r '.ipv4[0]' <<<"$created")
else
  REGION=${PIAB_TEST_REGION:-tor1}
  fingerprint=$(ssh-keygen -l -E md5 -f "$SSH_KEY.pub" | awk '{print $2}' | sed 's/^MD5://')
  if ! api GET "/account/keys/$fingerprint" >/dev/null 2>&1; then
    say "Adding the test SSH key to DigitalOcean"
    api POST /account/keys "$(jq -nc --arg k "$(cat "$SSH_KEY.pub")" '{name: "piab-test", public_key: $k}')" >/dev/null
  fi
  user_data=$(git show "$SHA:src/user-data.sh" \
    | sed -e "s/^export ADMIN_PASSWORD=''$/export ADMIN_PASSWORD='$ADMIN_PASSWORD'/" \
          -e "s/^PIAB_RELEASE='[^']*'$/PIAB_RELEASE='$SHA'/")
  grep -q "^PIAB_RELEASE='$SHA'$" <<<"$user_data" || die "couldn't set PIAB_RELEASE in src/user-data.sh"
  body=$(jq -nc --arg region "$REGION" --arg name "$NAME" --arg tag "$TAG" --arg fp "$fingerprint" \
      --arg ud "$user_data" \
      '{name: $name, region: $region, size: "s-1vcpu-1gb", image: "ubuntu-24-04-x64",
        ssh_keys: [$fp], tags: [$tag], user_data: $ud}')
  SERVER_ID=$(api POST /droplets "$body" | jq -r '.droplet.id')
  deadline=$((SECONDS + 300))
  until [[ -n "$IP" ]]; do
    (( SECONDS < deadline )) || die "the Droplet got no public address within 5 minutes"
    sleep 5
    IP=$(api GET "/droplets/$SERVER_ID" | jq -r '.droplet.networks.v4[] | select(.type == "public") | .ip_address')
  done
fi
echo "server: $SERVER_ID at $IP" >> "$WORK/notes.txt"
say "Created $NAME ($SERVER_ID) at $IP"
START=$SECONDS

# --- Helpers for the checks ----------------------------------------------------

SSH_OPTS=(-i "$SSH_KEY" -o IdentitiesOnly=yes -o BatchMode=yes -o ConnectTimeout=10 -o LogLevel=ERROR
          -o StrictHostKeyChecking=accept-new -o UserKnownHostsFile="$WORK/known_hosts")
# Commands are expanded locally on purpose (they include values from here).
# shellcheck disable=SC2029
rssh() { ssh "${SSH_OPTS[@]}" "root@$IP" "$@"; }
elapsed() { printf '%dm%02ds' $(( (SECONDS - START) / 60 )) $(( (SECONDS - START) % 60 )); }

# wait_until <description> <timeout seconds> <command...>
wait_until() {
  local what=$1 deadline=$((SECONDS + $2))
  shift 2
  until "$@" >/dev/null 2>&1; do
    if (( SECONDS >= deadline )); then
      fail "$what (gave up after $(elapsed))"
      return 1
    fi
    sleep 10
  done
  pass "$what ($(elapsed))"
}

page() { curl -s -m 10 "http://$IP/"; }
progress_page_up() { page | grep -q 'Plone in a Box'; }
setup_done() { rssh "grep -q '^\[plone-in-a-box\] Finished' /var/log/plone-in-a-box.log"; }
setup_failed() {
  page | grep -q "Setup didn't finish" \
    || rssh "grep -q '^\[plone-in-a-box\] Setup failed' /var/log/plone-in-a-box.log" 2>/dev/null
}
setup_done_or_failed() { setup_done || setup_failed; }
login() {
  curl -s -m 20 -X POST "http://$IP/++api++/@login" -H 'Accept: application/json' \
      -H 'Content-Type: application/json' --data "$(jq -nc --arg p "$1" '{login: "admin", password: $p}')" \
    | jq -er '.token'
}
old_password_rejected() { ! login "$ADMIN_PASSWORD"; }
site_is_plone() { ! page | grep -q 'Plone in a Box</title>' && curl -sf -m 10 "http://$IP/++api++/" | jq -e '."@id"' >/dev/null; }
port_closed() {
  local timeout=(-w 5)
  # macOS nc needs -G for the connection timeout.
  if nc -h 2>&1 | grep -qE '^[[:space:]]+-G'; then timeout+=(-G 5); fi
  if nc -z "${timeout[@]}" "$IP" "$1" 2>/dev/null; then return 1; fi
}
count_in_log() { rssh "grep -c '^\[plone-in-a-box\] $1' /var/log/plone-in-a-box.log || true"; }

# --- Setup -------------------------------------------------------------------------

wait_until "progress page is up" 600 progress_page_up || true
wait_until "setup finished or failed" 2400 setup_done_or_failed || exit 1
rssh 'cat /var/log/plone-in-a-box.log' > "$WORK/setup.log" 2>/dev/null || true
if setup_failed; then
  fail "setup failed; log saved to $WORK/setup.log"
  grep '^\[plone-in-a-box\]' "$WORK/setup.log" | tail -5
  exit 1
fi
pass "setup finished: $(grep '^\[plone-in-a-box\] Finished' "$WORK/setup.log")"
grep '^\[plone-in-a-box\]' "$WORK/setup.log" | grep -i 'swap\|restart\|continuing' | sed 's/^/      /' || true

wait_until "the site is Plone, not the progress page" 300 site_is_plone || true

# --- Admin password ---------------------------------------------------------------

if (( GENERATED )); then
  ADMIN_PASSWORD=$(rssh "awk '/^Password:/ {print \$2}' /root/plone-credentials.txt" 2>/dev/null || true)
  check "generated password is in /root/plone-credentials.txt" test -n "$ADMIN_PASSWORD"
  echo "generated admin password: $ADMIN_PASSWORD" >> "$WORK/notes.txt"
else
  check "credentials file doesn't contain the chosen password" \
    rssh "! grep -qF -- '$ADMIN_PASSWORD' /root/plone-credentials.txt"
fi
check "admin can log in" login "$ADMIN_PASSWORD"

if token=$(login "$ADMIN_PASSWORD"); then
  curl -s -m 20 "http://$IP/++api++/@system" -H 'Accept: application/json' -H "Authorization: Bearer $token" \
    | jq -r '"      Plone \(.plone_version), plone.restapi \(.plone_restapi_version), Zope \(.zope_version), Python \(.python_version | split(" ")[0]), Pillow \(.pil_version)"' \
    2>/dev/null || true
fi

NEW_PASSWORD=$(openssl rand -base64 24 | tr -dc 'A-Za-z0-9' | cut -c1-20)
echo "password after plone-reset-admin-password: $NEW_PASSWORD" >> "$WORK/notes.txt"
reset_output=$(printf '%s\n%s\n' "$NEW_PASSWORD" "$NEW_PASSWORD" \
  | ssh -tt "${SSH_OPTS[@]}" "root@$IP" plone-reset-admin-password 2>&1 || true)
check "plone-reset-admin-password reports success" grep -q 'has been changed' <<<"$reset_output"
check "the new password works" login "$NEW_PASSWORD"
check "the old password no longer works" old_password_rejected

# --- Network -------------------------------------------------------------------------

for port in 5432 8080 3000; do
  check "port $port is closed from outside" port_closed "$port"
done

# --- Server state ---------------------------------------------------------------------

mem=$(rssh "awk '/MemTotal|SwapTotal/ {s += \$2} END {print s}' /proc/meminfo")
rssh 'free -m' | sed 's/^/      /'
check "memory plus swap is at least 3 GB" test "$mem" -ge 3000000
check "resume files are gone" rssh '! test -e /root/.plone-in-a-box-resume && ! test -e /etc/systemd/system/plone-in-a-box-resume.service'
if rssh 'test -e /var/run/reboot-required'; then
  say "NOTE  /var/run/reboot-required exists (updates released during setup can cause this)"
else
  pass "no restart required"
fi

# --- Restarts -------------------------------------------------------------------------

continued=$(count_in_log 'Continuing setup')
say "Recreating the backend container"
rssh 'docker compose --project-directory /opt/plone up -d --force-recreate backend' >/dev/null 2>&1 || true
wait_until "password still works after recreating the backend" 300 login "$NEW_PASSWORD" || true

say "Restarting the server"
rssh 'systemctl reboot' >/dev/null 2>&1 || true
sleep 30
wait_until "SSH is back after the restart" 600 rssh true || exit 1
wait_until "site works after the restart" 600 login "$NEW_PASSWORD" || true
check "setup didn't run again after the restart" test "$(count_in_log 'Continuing setup')" = "$continued"
check "setup finished exactly once" test "$(count_in_log 'Finished')" = 1

# --- Result -------------------------------------------------------------------------------

if (( FAILURES )); then
  say "$FAILURES check(s) failed after $(elapsed). Details: $WORK"
  exit 1
fi
say "All checks passed after $(elapsed)"
