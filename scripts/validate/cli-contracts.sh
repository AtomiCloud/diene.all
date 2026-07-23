#!/usr/bin/env bash
set -euo pipefail

contract="${1:-}"
[ -z "${contract}" ] && echo "❌ usage: $0 <contract>" >&2 && exit 2

case "${contract}" in
arch)
  test -f bin/bun-cli.ts
  test -f src/lib/kv/interfaces.ts
  test -f src/adapters/terminal/console-io.ts
  rg -q 'console\.|process\.(stdin|stdout|stderr|exitCode)|from .(chalk|ora|cli-progress|inquirer).' src/lib src/adapters/kv && echo '❌ terminal/shell IO leaked into src/lib or src/adapters/kv' >&2 && exit 1
  rg -q "from ['\"](\\.\\./)+adapters(?:/|['\"])" src/lib && echo '❌ src/lib imports an adapter (forbidden upward dependency)' >&2 && exit 1
  ;;
distroless)
  rg -Fx 'FROM gcr.io/distroless/cc-debian12:nonroot AS runtime' infra/Dockerfile
  ;;
nonroot)
  rg -F ':nonroot AS runtime' infra/Dockerfile
  ;;
release-backup-order)
  yq -o=json '.' atomi_release.yaml | jq -e '
    .plugins[0].module == "@semantic-release/exec" and
    .plugins[0].config.prepareCmd == "./scripts/release/backup-changelog.sh" and
    ([.plugins[].module] | index("@semantic-release/github") == null)'
  ;;
changelog-asset)
  test -f Changelog.old.md
  yq -o=json '.' atomi_release.yaml | jq -e '
    [.plugins[] | select(.module == "@semantic-release/git") | .config.assets[]] |
    index("Changelog.old.md") != null'
  rg -F -- '--release-notes ./IncrementalChangelog.md' scripts/release/publish.sh
  ;;
release-artifacts)
  yq -o=json '.' .goreleaser.yaml | jq -e '
    (.archives | length) > 0 and
    (.checksum.name_template | length) > 0 and
    ([.release.extra_files[].glob] | index("scripts/release/install.sh") != null)'
  ;;
nfpms)
  yq -o=json '.' .goreleaser.yaml | jq -e '
    [.nfpms[].formats[]] as $formats |
    ($formats | index("deb") != null) and ($formats | index("rpm") != null)'
  ;;
homebrew-cask)
  yq -o=json '.' .goreleaser.yaml | jq -e '
    (.homebrew_casks | length) > 0 and
    ([.homebrew_casks[].hooks.post.install] | join("\n") | contains("com.apple.quarantine"))'
  ;;
fury-wiring)
  rg -F './scripts/release/publish.sh' .github/workflows/cd.yaml
  rg -F './scripts/release/fury.sh' scripts/release/publish.sh
  stage_line="$(rg -nF 'goreleaser release --clean --skip=publish --release-notes ./IncrementalChangelog.md' scripts/release/publish.sh | cut -d: -f1)"
  fury_line="$(rg -nF './scripts/release/fury.sh' scripts/release/publish.sh | cut -d: -f1)"
  publish_line="$(rg -nF 'goreleaser release --clean --release-notes ./IncrementalChangelog.md' scripts/release/publish.sh | cut -d: -f1)"
  [ "${stage_line}" -lt "${fury_line}" ] && [ "${fury_line}" -lt "${publish_line}" ] || {
    echo '❌ packages must be staged and sent to Gemfury before GoReleaser publishes GitHub + cask' >&2
    exit 1
  }
  rg -F -- '--config "${credential_config}"' scripts/release/fury.sh
  ! rg -F '${FURY_TOKEN}@' scripts/release/fury.sh
  ;;
docker-release)
  yq -o=json '.' .github/workflows/cd.yaml | jq -e '.jobs.docker.uses == "./.github/workflows/⚡reusable-docker.yaml"'
  ;;
installer-checksum)
  rg -F 'checksums.txt' scripts/release/install.sh
  rg -e 'sha256sum -c|shasum -a 256' scripts/release/install.sh
  ;;
installer-timeouts)
  curl_lines="$(rg '^[[:space:]]*curl ' scripts/release)"
  [ -z "${curl_lines}" ] && echo "❌ no release curl commands found" >&2 && exit 1
  bad_lines="$(printf '%s\n' "${curl_lines}" | awk '!/--connect-timeout/ || !/--max-time/')"
  [ -n "${bad_lines}" ] && printf '❌ curl missing timeout guard:\n%s\n' "${bad_lines}" >&2 && exit 1
  ;;
installation-parity)
  rg -F 'scripts/release/install.sh' .goreleaser.yaml
  rg -F "name_template: '{{ .ProjectName }}_{{ .Os }}_{{ .Arch }}'" .goreleaser.yaml
  rg -F 'checksums.txt' .goreleaser.yaml
  rg -F 'bun-cli_<os>_<arch>.tar.gz' INSTALLATION.md
  ;;
nix-release-wiring)
  rg -F 'bun-cli = pkgs.stdenv.mkDerivation' nix/packages.nix
  rg -F 'nix build .#bun-cli' .github/workflows/cd.yaml
  ;;
*)
  echo "❌ unknown CLI contract: ${contract}" >&2
  exit 2
  ;;
esac

echo "✅ CLI contract passed: ${contract}"
