#!/usr/bin/env bash
set -euo pipefail

contract="${1:-}"
[ -z "${contract}" ] && echo "❌ usage: $0 <contract>" >&2 && exit 2

case "${contract}" in
arch)
  test -f bin/releaser.ts
  test -f src/lib/release/ports.ts
  test -f src/adapters/terminal/console-io.ts
  ! rg -n 'console\.|process\.(stdin|stdout|stderr|exitCode)|Bun\.(spawn|file)|node:(fs|path|process)|from .commander.' src/lib
  ! rg -n 'from .*(/|^)adapters/' src/lib
  for config in knip.json knip.llm.json knip.production.json knip.production.llm.json; do
    jq -e '.entry | index("bin/releaser.ts") != null' "${config}" >/dev/null || {
      echo "❌ ${config} must retain bin/releaser.ts as a real entry" >&2
      exit 1
    }
  done
  ;;
release-backup-order)
  yq -o=json '.' atomi_release.yaml | jq -e '
    .schemaVersion == 2 and
    .release.hooks.prepare[0] == {"phase":"beforeWrite","command":"./scripts/release/backup-changelog.sh"} and
    .release.hooks.prepare[1].phase == "afterWrite" and
    .release.github == false'
  ;;
changelog-asset)
  test -f Changelog.old.md
  yq -o=json '.' atomi_release.yaml | jq -e '
    .release.commit.assets | index("Changelog.old.md") != null'
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
  rg -F 'releaser_<os>_<arch>.tar.gz' INSTALLATION.md
  ;;
nix-release-wiring)
  rg -F 'releaser = pkgs.stdenv.mkDerivation' nix/packages.nix
  rg -F 'nix build .#releaser' .github/workflows/cd.yaml
  ;;
*)
  echo "❌ unknown CLI contract: ${contract}" >&2
  exit 2
  ;;
esac

echo "✅ CLI contract passed: ${contract}"
