# Installing `releaser`

`releaser` is a standalone binary; Bun and Node are not required at runtime.
Releases publish through the `atomicloud` Gemfury account and the
`AtomiCloud/homebrew-tap` cask repository.

## Debian and Ubuntu

```bash
echo "deb [trusted=yes] https://apt.fury.io/atomicloud/ /" | sudo tee /etc/apt/sources.list.d/atomicloud.list
sudo apt update
sudo apt install releaser
```

## Fedora, RHEL, and CentOS

Add `https://yum.fury.io/atomicloud/` as a package repository, then install:

```bash
sudo dnf install releaser
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
