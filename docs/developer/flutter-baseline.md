# Flutter baseline

This node is a four-landscape Flutter application baseline with reproducible
Flutter, Dart, Android, and release tooling supplied by Nix.

## Local workflow

```bash
pls setup
pls mobile:analyze
pls mobile:test
pls mobile:build-flavors
```

Use `--flavor <landscape>` together with
`--dart-define=FLUTTER_BASE_LANDSCAPE=<landscape>`. Effective configuration is
`config/base.yaml` → `config/<landscape>.yaml` → approved compile-time defines.
Landscape selection never inspects hostnames, application IDs, or runtime
environment variables.

## Identity grammar

`lpsm.yaml` is the chain top. Store IDs are
`<domain>.<landscape>.<platform>.<service>.app`; the Logto callback scheme is
that app ID, and the App Group is `group.<app-id>`. Run
`scripts/ci/lpsm-lint.sh` after changing identity-bearing files.

## Generation

- `pls mobile:generate-sdk` regenerates the OA3 client.
- `pls mobile:generate-translations` regenerates Slang output.
- `pls mobile:generate-config` regenerates the JSON schema.
- `flutter pub run flutter_launcher_icons` regenerates every flavor icon set.

Generated output is checked for freshness in pre-commit and CI.

## Donor and stamp releases

CD builds one raichu donor per platform with placeholder version fields, then
fans out small stamp jobs per landscape. A stamp changes packaging identity,
display name, icon selection, version, signing, and the donor-selected raichu
config asset. Replacing that selected asset keeps the landscape baked into the
artifact without runtime detection while preserving one compiled donor.

Android donors are debug-signed and re-signed with the upload key. iOS profiles
are discovered from the Xcode project, fetched per signable target, checked for
the App Group, and re-signed inner-to-outer. Stamp doctors validate the packed
artifact before upload.

Apple identifiers, App Groups, capabilities, and numeric ASC app IDs are
registered locally by an App Manager with `pls mobile:register-apple`.
