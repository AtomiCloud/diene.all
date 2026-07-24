# Lithium distribution

This repository publishes one semver for the Aldehyde Logto fork image reference
and the `diene-lithium` / `diene-lithium-primordial` OCI chart pair. Release
stamping requires both chart versions, both app versions, and `image.tag` to match.
Garden target-pull may replace the tag with a verified `image.digest`; local modes
retain the same versioned tag for their build/local-artifact contract. The app chart is a
read-only consumer of the boot material minted by logto-operator; it never writes
Infisical or creates a credential.

`FLEET` derives `api.lithium.<platform>.<vlandscape>.cluster.atomi.cloud`, exposes
the core endpoint through a LoadBalancer, consumes a database URL and the exact
`/{platform}/lithium` boot pair using ExternalSecrets, and has no private service
path. The primordial chart emits one database `PlatformDependency` per vlandscape
and one `VirtualLandscapeService` per serving row.

`GARDEN-LOCAL` derives exact issuers: lapras/hosted profiles use HTTPS dotted
names, while ditto/rotom/absol use the allocated localhost HTTP port. It exposes
only `lithium-public` through a versioned default-deny public filter; the raw,
cluster-local `lithium-management` Service is for the local operator and denied
by every exposure rail. It uses direct local Secret references and lifecycle labels
for Garden instance UID and allocation generation. Hosted profiles leave their edge,
certificate, and Boron ownership to ENTEI.

The credential gate uses `busybox:1.36.1`, rather than assuming a shell in Logto.
Upstream Logto `1.41.0` was inspected: it exposes 3001 and starts as `npm run
start` from `/etc/logto`; its image default user is root, so the chart keeps a
non-root UID but does not make the root filesystem read-only. The k3d runner proves
chart installation with Garden-provided fixture Secrets. Fork-image startup behavior
remains owned and integration-tested by the external Aldehyde fork repository.
