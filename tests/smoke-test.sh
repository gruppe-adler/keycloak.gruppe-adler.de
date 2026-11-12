#!/usr/bin/env bash
# Smoke test for a built Keycloak image: starts it next to a throwaway
# Postgres, waits for it to come up and checks that both extensions are loaded.
#
# Usage: tests/smoke-test.sh <image>
set -euo pipefail

IMAGE="${1:?usage: $0 <image>}"
PORT="${PORT:-8080}"
BASE="http://localhost:${PORT}"
RUN_ID="kc-smoke-$$"
NET="$RUN_ID"
DB="$RUN_ID-db"
KC="$RUN_ID-kc"

cleanup() {
  status=$?
  if [ "$status" -ne 0 ]; then
    echo "::group::Keycloak logs"
    docker logs "$KC" 2>&1 || true
    echo "::endgroup::"
  fi
  docker rm -f "$KC" "$DB" >/dev/null 2>&1 || true
  docker network rm "$NET" >/dev/null 2>&1 || true
  exit "$status"
}
trap cleanup EXIT

fail() { echo "FAIL: $*" >&2; exit 1; }

docker network create "$NET" >/dev/null

docker run -d --name "$DB" --network "$NET" \
  -e POSTGRES_DB=keycloak -e POSTGRES_USER=keycloak -e POSTGRES_PASSWORD=keycloak \
  postgres:17-alpine >/dev/null

echo "Waiting for Postgres to start..."
for _ in $(seq 1 30); do
  # -h forces TCP, so the temporary socket-only server during init doesn't count.
  docker exec "$DB" pg_isready -q -h localhost -U keycloak && break
  sleep 1
done
docker exec "$DB" pg_isready -q -h localhost -U keycloak || fail "Postgres did not become ready in time"

# Runs the image's own entrypoint/CMD (start --optimized); only runtime
# options are passed in, so a missing build-time setting would fail here.
docker run -d --name "$KC" --network "$NET" -p "${PORT}:8080" \
  -e KC_DB_URL="jdbc:postgresql://$DB:5432/keycloak" \
  -e KC_DB_USERNAME=keycloak -e KC_DB_PASSWORD=keycloak \
  -e KC_HTTP_ENABLED=true -e KC_HOSTNAME_STRICT=false \
  -e KC_BOOTSTRAP_ADMIN_USERNAME=admin -e KC_BOOTSTRAP_ADMIN_PASSWORD=admin \
  "$IMAGE" >/dev/null

echo "Waiting for Keycloak to start..."
for _ in $(seq 1 90); do
  if [ "$(docker inspect -f '{{.State.Running}}' "$KC")" != "true" ]; then
    fail "Keycloak container exited during startup"
  fi
  if curl -fs -o /dev/null "$BASE/realms/master"; then
    break
  fi
  sleep 2
done
curl -fsS -o /dev/null "$BASE/realms/master" || fail "Keycloak did not become ready in time"
echo "OK: Keycloak is up"

# keycloak-grad-arma3-squad: realm resource with static files that need no config.
curl -fsS -o /dev/null "$BASE/realms/master/arma3-squad/squad.dtd" \
  || fail "arma3-squad endpoint not reachable (extension not loaded?)"
echo "OK: arma3-squad extension serves squad.dtd"

# keycloak-steam-idp: must show up as an identity provider type in serverinfo.
TOKEN="$(curl -fsS "$BASE/realms/master/protocol/openid-connect/token" \
  -d grant_type=password -d client_id=admin-cli -d username=admin -d password=admin \
  | jq -r .access_token)"
[ -n "$TOKEN" ] && [ "$TOKEN" != "null" ] || fail "could not get an admin token"

curl -fsS -H "Authorization: Bearer $TOKEN" "$BASE/admin/serverinfo" \
  | jq -e '.identityProviders | any(.id == "steam-idp")' >/dev/null \
  || fail "steam-idp identity provider not registered (extension not loaded?)"
echo "OK: steam-idp identity provider is registered"

if docker logs "$KC" 2>&1 | grep -E '^\S+ \S+ ERROR'; then
  fail "Keycloak logged errors during startup"
fi
echo "OK: no errors in the startup log"

echo "Smoke test passed."
