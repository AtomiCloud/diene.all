# Releaser

<!-- ### nix-root -->
<!-- #### source: main -->

The reproducible development environment is managed by Nix. Enter it through
direnv, then use the `pls` tasks from the loaded shell.

<!-- ### workspace -->
<!-- #### source: workspace -->

`releaser` is a standalone Bun/TypeScript binary for conventional release
calculation, changelog generation, commit linting, Git publication, optional
GitHub release side effects, and legacy configuration migration. It replaces
runtime semantic-release plugin installation, `sg`, Python Gitlint, and the
generated `.releaserc.yaml` split with one strict configuration.

## CLI

```text
releaser release [--dry-run] [-c <path>]
releaser lint-commit <msgfile> [-c <path>]
releaser next
releaser changelog
releaser conventions
releaser migrate
```

Only `release` without `--dry-run` mutates Git or publishes. `next`,
`changelog`, and dry-run release are previews; `conventions` replaces only its
configured document; `migrate` atomically rewrites v1 configuration and removes
legacy generated files.

## Development

- `pls setup` installs the locked dependencies.
- `pls lint` runs repository gates.
- `pls test` runs unit, integration, and compiled-binary SIT tiers.
- `pls build` bundles the source entry point.
- `pls compile` emits Linux x64-baseline, Linux arm64, and Darwin arm64 binaries.
- `pls preview -- --help` runs this host's compiled binary.

The architecture points inward: `src/lib` contains pure configuration, commit,
version, notes, and orchestration logic; `src/adapters` owns filesystem, Git,
HTTP, process, and terminal I/O; [bin/releaser.ts](bin/releaser.ts) is the sole
composition root.

## Distribution

GoReleaser packages the three precompiled binaries as archives, checksums,
Debian/RPM packages, a Homebrew cask, and the checksum-verifying installer. Nix
exposes `.#releaser`. Docker is intentionally unsupported because release hooks
and Git operations require an ordinary host environment.

See [INSTALLATION.md](INSTALLATION.md), the [Bun baseline](docs/developer/bun-baseline.md),
and the [domain guide](docs/domain/releaser.md).

<!-- ### shared -->
<!-- #### source: shared -->

Shared engineering standards live under [docs/standards/](docs/standards/).

<!-- ### releaser -->
<!-- #### source: releaser -->

The release vocabulary, lint rules, hooks, assets, and distribution ownership
are defined in [atomi_release.yaml](atomi_release.yaml). No runtime path invokes a
package manager or dynamically loads plugins.
