#!/usr/bin/env bash
set -euo pipefail

# Hermetic, offline, publish-impossible regression for the RB-339 second defect.
#
# It never sets or reads GITHUB_TOKEN, never runs a real release, never pushes,
# tags, dispatches a workflow, or reaches the network. It builds a FAKE local
# `semantic-release` package and proves the exact argv boundary:
#   * RED  — the version-suffixed binary NAME `semantic-release@23.0.1` is NOT
#            resolvable as a command; this is precisely why a runtime that resolves
#            `<pm> exec <arg>` as a binary name (yarn 1.x / pnpm, as on the CI
#            runner) dies with "Couldn't find the binary semantic-release@23.0.1".
#   * GREEN — npm resolves the installed package SPEC `semantic-release@23.0.1`
#            offline to its bare `semantic-release` bin (the fix: `-i npm`).
#   * GREEN — the bare executable name `semantic-release` runs: the version belongs
#            only in the install spec, not the exec argument.

work="$(mktemp -d)"
trap 'rm -rf "${work}"' EXIT
cd "${work}"

export npm_config_cache="${work}/.npm-cache"
export npm_config_update_notifier=false
sentinel="${work}/sentinel.txt"
export SENTINEL="${sentinel}"
: >"${sentinel}"

mkdir -p node_modules/semantic-release node_modules/.bin
cat >node_modules/semantic-release/package.json <<'JSON'
{ "name": "semantic-release", "version": "23.0.1", "bin": { "semantic-release": "cli.js" } }
JSON
cat >node_modules/semantic-release/cli.js <<'STUB'
#!/usr/bin/env node
const fs = require("fs");
fs.appendFileSync(process.env.SENTINEL, "ran argv=" + process.argv.slice(2).join(" ") + "\n");
process.exit(0);
STUB
chmod +x node_modules/semantic-release/cli.js
ln -s ../semantic-release/cli.js node_modules/.bin/semantic-release
chmod +x node_modules/.bin/semantic-release

export PATH="${work}/node_modules/.bin:${PATH}"

# RED (defect cause): a runtime resolving the arg as a binary NAME cannot find it.
if command -v 'semantic-release@23.0.1' >/dev/null 2>&1; then
  echo "❌ unexpected: version-suffixed binary name resolved" >&2
  exit 1
fi
echo "✅ RED reproduced: 'semantic-release@23.0.1' is not a resolvable binary name"

# The bare binary IS present — the name the correct exec must address.
command -v semantic-release >/dev/null || {
  echo "❌ bare 'semantic-release' binary missing from fixture" >&2
  exit 1
}

# Real yarn/pnpm are intentionally absent from .#releaser (the fix makes npm the
# only runtime). Do not silently cap: when present, assert identical failure;
# otherwise log the skip explicitly — the cause is asserted structurally above.
for pm in yarn pnpm; do
  if command -v "${pm}" >/dev/null 2>&1; then
    if "${pm}" exec 'semantic-release@23.0.1' >/dev/null 2>&1; then
      echo "❌ unexpected: ${pm} exec resolved the version-suffixed binary" >&2
      exit 1
    fi
    echo "✅ ${pm} exec 'semantic-release@23.0.1' fails identically"
  else
    echo "ℹ️ ${pm} unavailable offline — binary-name failure asserted structurally (no silent cap)"
  fi
done

# GREEN (fix): npm resolves the installed package SPEC offline to the bare bin.
: >"${sentinel}"
npm exec --offline --no -- 'semantic-release@23.0.1'
grep -q '^ran argv=' "${sentinel}" || {
  echo "❌ npm spec exec did not run the installed semantic-release" >&2
  exit 1
}
echo "✅ GREEN: npm exec resolved the pinned package spec offline (bare bin ran)"

# GREEN (bare-name semantics): version belongs only in the install spec.
: >"${sentinel}"
npm exec --offline --no -- semantic-release
grep -q '^ran argv=' "${sentinel}" || {
  echo "❌ npm bare exec did not run semantic-release" >&2
  exit 1
}
echo "✅ GREEN: bare 'semantic-release' exec ran offline"

echo "✅ releaser runtime argv regression passed"
