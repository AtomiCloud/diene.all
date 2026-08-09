# Installing `bun-cli`

`bun-cli` ships as a standalone binary (no Bun/Node runtime required) to every major channel.
Pick the one that fits your platform. Release automation mirrors Debian/RPM packages to the
Gemfury account `atomicloud` and publishes a cask to `AtomiCloud/homebrew-tap`.

> **macOS caveat — unsigned binaries.** The binaries are not code-signed. On macOS, Gatekeeper
> quarantines them on first run. Clear the quarantine attribute after install:
>
> ```bash
> xattr -d com.apple.quarantine "$(command -v bun-cli)"
> ```

## Debian / Ubuntu (`.deb`)

The `atomicloud` Gemfury repository does not currently publish a GPG key. Do not add it to APT
with signature verification disabled. Until repository signing is provisioned, download the
matching `bun-cli_<version>_linux_<amd64-or-arm64>.deb` and `checksums.txt` assets from the same
[GitHub release](https://github.com/AtomiCloud/diene.bun-cli/releases), then verify and install:

```bash
package='bun-cli_<version>_linux_<amd64-or-arm64>.deb'
grep " ${package}$" checksums.txt | sha256sum --check
sudo apt install "./${package}"
```

## Fedora / RHEL / CentOS (`.rpm`)

The same signing prerequisite applies to the Gemfury Yum repository. Until its repository metadata
and RPM packages are signed, download the matching `bun-cli_<version>_linux_<amd64-or-arm64>.rpm`
and `checksums.txt` from the same GitHub release, then verify and install:

```bash
package='bun-cli_<version>_linux_<amd64-or-arm64>.rpm'
grep " ${package}$" checksums.txt | sha256sum --check
sudo dnf install "./${package}"
```

## Homebrew (macOS)

```bash
brew install --cask atomicloud/tap/bun-cli
# AtomiCloud/homebrew-tap — a cask is published on each release
```

> The baseline publishes a Homebrew **cask** (not a formula): GoReleaser deprecated formula
> generation for pre-compiled binaries in favour of casks. The cask strips the macOS quarantine
> attribute on install automatically, so no manual `xattr` step is needed for the brew path.

## Docker

```bash
docker run --rm ghcr.io/atomicloud/diene.bun-cli/diene-bun-cli:latest --help

# the sample commands reach Redis via REDIS_HOST/REDIS_PORT (127.0.0.1 is the container itself)
docker run --rm -e REDIS_HOST=my-redis ghcr.io/atomicloud/diene.bun-cli/diene-bun-cli:latest set ns key value
```

## Nix

```bash
# build from the flake
nix build github:AtomiCloud/diene.bun-cli#bun-cli
./result/bin/bun-cli --version

# or run directly
nix run github:AtomiCloud/diene.bun-cli#bun-cli -- --help
```

## GitHub release (one-line installer)

Downloads the right archive for your OS/arch, verifies the checksum, and installs to
`~/.local/bin` (override with `BIN_DIR`):

```bash
curl -fsSL --connect-timeout 30 --max-time 600 https://github.com/AtomiCloud/diene.bun-cli/releases/latest/download/install.sh | bash
```

Or grab a specific archive manually from the
[releases page](https://github.com/AtomiCloud/diene.bun-cli/releases) — `bun-cli_<os>_<arch>.tar.gz`
— verify it against `checksums.txt`, and extract the `bun-cli` binary onto your `PATH`.

## Verify

```bash
bun-cli --version
bun-cli --help
```
