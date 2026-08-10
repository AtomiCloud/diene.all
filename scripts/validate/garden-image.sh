#!/usr/bin/env bash
set -euo pipefail

# Garden image rail, with a documented degradation.
#
# The image's load-bearing claims are three: it runs as a NUMERIC nonroot user
# (the chart pins runAsUser: 1001 and a mismatch makes every pod CrashLoop), it
# carries `public/` and `.next/static/` (which `output: 'standalone'` does NOT
# trace, so an app missing them boots and then serves no assets), and it boots
# `server.js`.
#
# Where docker is reachable those claims are checked against a REAL built image.
# Where it is not, they are checked statically against the recipe — strictly
# weaker, labelled as such in the output. CI builds the image for real.

dockerfile="infra/Dockerfile.garden"
image="diene-nextjs-frontend-garden-probe:$$"

[ -f "${dockerfile}" ] || {
  echo "❌ ${dockerfile} is missing" >&2
  exit 1
}

assert_recipe() {
  # A numeric uid is what the chart's securityContext can actually agree with;
  # `USER nextjs` alone is satisfied by any uid the base image happens to assign.
  grep -qE '^RUN addgroup -g 1001 -S nodejs && adduser -u 1001 -S nextjs' "${dockerfile}" || {
    echo "❌ the recipe does not create a numeric uid-1001 nonroot user" >&2
    exit 1
  }
  grep -qE '^USER nextjs$' "${dockerfile}" || {
    echo "❌ the recipe does not drop to the nonroot user" >&2
    exit 1
  }
  grep -qE '^COPY --from=build .* /app/\.next/static \./\.next/static$' "${dockerfile}" || {
    echo "❌ the recipe does not copy .next/static — the app would ship no client chunks" >&2
    exit 1
  }
  grep -qE '^COPY --from=build .* /app/public \./public$' "${dockerfile}" || {
    echo "❌ the recipe does not copy public/ — the app would ship no static assets" >&2
    exit 1
  }
  grep -qE '^CMD \["node", "server\.js"\]$' "${dockerfile}" || {
    echo "❌ the recipe does not boot server.js" >&2
    exit 1
  }
}

assert_recipe

if ! docker info >/dev/null 2>&1; then
  echo "⚠️ DEGRADED: no reachable docker daemon — asserting the recipe only, not a built image."
  echo "⚠️ CI's image job builds and inspects the real artifact."
  echo "✅ Garden image green (DEGRADED: static recipe assertions)"
  exit 0
fi

cleanup() {
  docker image rm -f "${image}" >/dev/null 2>&1 || true
}
trap cleanup EXIT

echo "🐳 Building ${dockerfile}..."
docker build -f "${dockerfile}" -t "${image}" . >/dev/null

echo "🔎 Asserting the image runs as numeric nonroot..."
uid="$(docker run --rm --entrypoint sh "${image}" -c 'id -u' | tr -d '[:space:]')"
[ "${uid}" = "1001" ] || {
  echo "❌ image runs as uid '${uid}', want 1001" >&2
  exit 1
}

echo "🔎 Asserting the asset trees are present..."
for path in .next/static public server.js config; do
  docker run --rm --entrypoint sh "${image}" -c "test -e '/app/${path}'" || {
    echo "❌ image is missing /app/${path}" >&2
    exit 1
  }
done

# An empty static tree is the same outage as a missing one, so the directory
# being non-empty is the assertion that matters.
count="$(docker run --rm --entrypoint sh "${image}" -c 'ls -1 /app/.next/static | wc -l' | tr -d '[:space:]')"
[ "${count}" -gt 0 ] || {
  echo "❌ /app/.next/static is empty — the app would serve no client chunks" >&2
  exit 1
}

echo "✅ Garden image green (real build)"
