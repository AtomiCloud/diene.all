#!/usr/bin/env bash
set -euo pipefail

# The public upstream image is the runnable 1.41.0 compatibility fixture. Felix
# runs the same test with the private Aldehyde fork image before publishing it.
image="${BOOTSTRAP_RUNTIME_IMAGE:-ghcr.io/logto-io/logto:1.41.0}"
suffix="lithium-bootstrap-$RANDOM-$$"
network="${suffix}"
database="${suffix}-database"

cleanup() {
  docker rm -f "${database}" >/dev/null 2>&1 || true
  docker network rm "${network}" >/dev/null 2>&1 || true
}
trap cleanup EXIT

docker network create "${network}" >/dev/null
docker run -d --rm --name "${database}" --network "${network}" \
  -e POSTGRES_PASSWORD=postgres -e POSTGRES_DB=logto postgres:17-alpine >/dev/null

for _ in $(seq 1 30); do
  if docker exec "${database}" pg_isready -U postgres -d logto >/dev/null 2>&1; then
    break
  fi
  sleep 1
done
docker exec "${database}" pg_isready -U postgres -d logto >/dev/null

bootstrap() {
  docker run --rm --network "${network}" --user 10001:10001 \
    --tmpfs /etc/logto/packages/cli/alteration-scripts:uid=10001,gid=10001 \
    -e DB_URL="postgres://postgres:postgres@${database}:5432/logto" \
    --entrypoint npm "${image}" run cli db seed -- --swe --dapc
}

# A fresh database must create the schema; a second execution proves --swe makes
# the bootstrap safe when the Pod is recreated.
bootstrap
bootstrap
test "$(docker exec "${database}" psql -U postgres -d logto -Atc 'select count(*) from logto_configs')" -gt 0
echo "✅ Lithium fresh database bootstrap validation passed"
