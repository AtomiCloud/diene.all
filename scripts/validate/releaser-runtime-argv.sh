#!/usr/bin/env bash
set -euo pipefail

# Hermetic, offline, publish-impossible regression for the RB-339 second defect.
#
# It never sets or reads GITHUB_TOKEN, never runs a real release, never pushes,
# tags, dispatches a workflow, or reaches the network. It builds a FAKE local
# `semantic-release` package and proves the exact argv boundary with a REAL
# Yarn Classic executable:
#   * RED  — `yarn exec semantic-release@23.0.1` fails nonzero and NEVER runs the
#            package, because Yarn resolves the exec ARG as a binary NAME and no
#            `semantic-release@23.0.1` binary exists ("Couldn't find the binary
#            semantic-release@23.0.1"). This is exactly the failed CI Release job.
#   * CTRL — the SAME Yarn runs the BARE binary `semantic-release` successfully;
#            this isolates the `@23.0.1` suffix as the sole cause and proves the
#            Yarn is a real working Yarn, not a stub/emulator.
#   * GREEN — npm resolves the installed package SPEC `semantic-release@23.0.1`
#            offline to its bare `semantic-release` bin (the fix: `-i npm`).
#   * GREEN — the bare executable name `semantic-release` runs: the version belongs
#            only in the install spec, not the exec argument.
#
# The real Yarn Classic is provided to this fixture OUT-OF-BAND through
# RB339_YARN_CLASSIC_BIN (a Nix store path built from the pinned nixpkgs). Yarn
# is deliberately NOT on the `.#releaser` runtime PATH — the production release
# runtime stays npm-only, and this script asserts that below.

work="$(mktemp -d)"
trap 'rm -rf "${work}"' EXIT
cd "${work}"

export HOME="${work}"
export npm_config_cache="${work}/.npm-cache"
export npm_config_update_notifier=false
sentinel="${work}/sentinel.txt"
export SENTINEL="${sentinel}"
: >"${sentinel}"

sentinel_ran() { grep -q '^ran argv=' "${sentinel}"; }
reset_sentinel() { : >"${sentinel}"; }

# --- Build the FAKE local semantic-release package (no network, no real release). ---
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

# --- Production-runtime property: the real .#releaser shell is npm-only. ---
# yarn/pnpm MUST be absent from the release runtime PATH; the fix relies on npm
# being auto-selected. The Yarn used for the old-red below is injected from the
# Nix store OUT of this runtime, never added to it.
for pm in yarn pnpm; do
  if command -v "${pm}" >/dev/null 2>&1; then
    echo "❌ ${pm} is on the .#releaser runtime PATH; the release runtime must be npm-only" >&2
    exit 1
  fi
done
echo "✅ .#releaser runtime is npm-only (no yarn/pnpm on PATH)"

# --- The bare binary IS present — the name the correct exec must address. ---
command -v semantic-release >/dev/null || {
  echo "❌ bare 'semantic-release' binary missing from fixture" >&2
  exit 1
}

# --- Real hermetic Yarn Classic old-red (load-bearing; no silent skip). ---
# A real Yarn 1.x binary is provided to the fixture out-of-band. This is NOT a
# command lookup, NOT a hand-written emulator, and NOT a network download.
: "${RB339_YARN_CLASSIC_BIN:?RB339_YARN_CLASSIC_BIN must point at a real Yarn Classic (1.x) binary}"
[ -x "${RB339_YARN_CLASSIC_BIN}" ] || {
  echo "❌ RB339_YARN_CLASSIC_BIN='${RB339_YARN_CLASSIC_BIN}' is not an executable" >&2
  exit 1
}
yarn_version="$("${RB339_YARN_CLASSIC_BIN}" --version)"
case "${yarn_version}" in
1.*) : ;;
*)
  echo "❌ provided Yarn is '${yarn_version}', expected Yarn Classic (1.x)" >&2
  exit 1
  ;;
esac
echo "ℹ️ using hermetic Yarn Classic ${yarn_version} at ${RB339_YARN_CLASSIC_BIN}"

# RED (defect cause): Yarn resolves the exec ARG as a binary NAME. The
# version-suffixed name `semantic-release@23.0.1` is not a binary in
# node_modules/.bin, so Yarn dies nonzero and NEVER runs the sentinel.
reset_sentinel
if "${RB339_YARN_CLASSIC_BIN}" exec 'semantic-release@23.0.1' >/dev/null 2>&1; then
  echo "❌ unexpected: 'yarn exec semantic-release@23.0.1' succeeded" >&2
  exit 1
fi
if sentinel_ran; then
  echo "❌ unexpected: 'yarn exec semantic-release@23.0.1' ran the fake package" >&2
  exit 1
fi
echo "✅ RED reproduced: 'yarn exec semantic-release@23.0.1' fails nonzero and never touches the sentinel"

# CONTROL: the SAME real Yarn runs the BARE binary name successfully and DOES
# touch the sentinel — isolating the `@23.0.1` suffix as the sole cause and
# proving the Yarn is real, not a stub that fails everything.
reset_sentinel
"${RB339_YARN_CLASSIC_BIN}" exec semantic-release
sentinel_ran || {
  echo "❌ 'yarn exec semantic-release' (bare) did not run the fake package" >&2
  exit 1
}
echo "✅ CONTROL: the same Yarn runs the bare 'semantic-release' (version belongs only in the install spec)"

# GREEN (fix): npm resolves the installed package SPEC offline to the bare bin.
reset_sentinel
npm exec --offline --no -- 'semantic-release@23.0.1'
sentinel_ran || {
  echo "❌ npm spec exec did not run the installed semantic-release" >&2
  exit 1
}
echo "✅ GREEN: npm exec resolved the pinned package spec offline (bare bin ran)"

# GREEN (bare-name semantics): version belongs only in the install spec.
reset_sentinel
npm exec --offline --no -- semantic-release
sentinel_ran || {
  echo "❌ npm bare exec did not run semantic-release" >&2
  exit 1
}
echo "✅ GREEN: bare 'semantic-release' exec ran offline"

echo "✅ releaser runtime argv regression passed"
