# Installing `releaser`

`releaser` ships as a standalone binary (no Bun/Node runtime required) to every major channel.
Pick the one that fits your platform. Release automation mirrors Debian/RPM packages to the
Gemfury account `atomicloud` and publishes a cask to `AtomiCloud/homebrew-tap`.

> **macOS caveat — unsigned binaries.** The binaries are not code-signed. On macOS, Gatekeeper
> quarantines them on first run. Clear the quarantine attribute after install:
>
> ```bash
> xattr -d com.apple.quarantine "$(command -v releaser)"
> ```

## Debian / Ubuntu (`.deb`)

The `atomicloud` Gemfury repository does not currently publish a GPG key. Do not add it to APT
with signature verification disabled. Until repository signing is provisioned, download the
matching `releaser_<version>_linux_<amd64-or-arm64>.deb` and `checksums.txt` assets from the same
[GitHub release](https://github.com/AtomiCloud/releaser/releases), then verify and install:

```bash
package='releaser_<version>_linux_<amd64-or-arm64>.deb'
grep " ${package}$" checksums.txt | sha256sum --check
sudo apt install "./${package}"
```

## Fedora / RHEL / CentOS (`.rpm`)

The same signing prerequisite applies to the Gemfury Yum repository. Until its repository metadata
and RPM packages are signed, download the matching `releaser_<version>_linux_<amd64-or-arm64>.rpm`
and `checksums.txt` from the same GitHub release, then verify and install:

```bash
package='releaser_<version>_linux_<amd64-or-arm64>.rpm'
grep " ${package}$" checksums.txt | sha256sum --check
sudo dnf install "./${package}"
```

## Homebrew on macOS

```bash
brew install --cask atomicloud/tap/releaser
```

The cask removes the quarantine attribute from the unsigned arm64 binary during
installation. Intel macOS is not a supported target.

## Nix

```bash
nix build github:AtomiCloud/releaser#releaser
./result/bin/releaser --version

nix run github:AtomiCloud/releaser#releaser -- --help
```

## GitHub release installer

The installer selects the supported OS/architecture archive, verifies it against
`checksums.txt`, and installs to `~/.local/bin` by default:

```bash
curl -fsSL --connect-timeout 30 --max-time 600 https://github.com/AtomiCloud/releaser/releases/latest/download/install.sh | bash
```

Manual downloads are available from the
[releases page](https://github.com/AtomiCloud/releaser/releases) as
`releaser_<os>_<arch>.tar.gz` archives.

## Verify

```bash
releaser --version
releaser --help
```
