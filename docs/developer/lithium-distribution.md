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
`/{platform}/lithium` boot pair and the C0 database folder `/database/lithium`
using ExternalSecrets, and has no private service path. Platform and environment
are SecretStore boundaries, not Infisical folder segments. The primordial chart emits one database `PlatformDependency` per vlandscape
and one `VirtualLandscapeService` per serving row.

ESO uses full Infisical folder-plus-key references: `/database/lithium/DB_URL`,
`/{platform}/lithium/SEED_M2M_CLIENT_ID`, and
`/{platform}/lithium/SEED_M2M_CLIENT_SECRET`. These are `remoteRef.key` values;
the chart does not use `remoteRef.property` for this separate-key contract.

Fleet consumes the platform-owned `carbon-store` SecretStore by default (and may
be configured with another existing platform store); Lithium never renders or owns
a SecretStore.

Fleet consumes the platform-owned `carbon-store` SecretStore by default (and may
be configured with another existing platform store); Lithium never renders or owns
a SecretStore.

`FLEET` keeps one LoadBalancer `lithium-public` Service: raw Logto serves both
OIDC and the required Management API `/api` on that canonical host. `GARDEN-LOCAL`
derives exact issuers: lapras/hosted profiles use HTTPS dotted
names, while ditto/rotom/absol use the allocated localhost HTTP port. It exposes
only `lithium-public` through a versioned default-deny public filter; the raw,
cluster-local `lithium-management` Service is for the local operator and denied
by every exposure rail. It uses direct local Secret references and lifecycle labels
for Garden instance UID and allocation generation. A chart-owned NetworkPolicy admits
the ordinary rail only to the public-filter port and the local operator identity only
to the raw management port. Hosted profiles leave their edge,
certificate, and Boron ownership to ENTEI.

The Garden filter is an explicit Logto `v1.41.0` allowlist, not a proxy for all
of `/api`: it permits OIDC discovery and JWKS at
`/oidc/.well-known/openid-configuration` and `/oidc/jwks`, OIDC auth/token/me,
device and session endpoints, the public `/api/experience` surface, social
callbacks, the pinned Experience SPA routes, and its `/assets` files. Management
paths such as `/api/applications` remain denied. The Docker-backed filter test
proves discovery, JWKS, Experience, and sign-in assets traverse the filter while
that Management path returns `404`.

The credential gate uses `busybox:1.36.1`, rather than assuming a shell in Logto.
Before the core container starts, a separate sequential `database-bootstrap` init
container runs the same Aldehyde image's `npm run cli db seed -- --swe --dapc`
command with only `DB_URL`. `--swe` makes the operation safe for an existing
schema; `--dapc` disables the seeded admin password breach call for the air-gapped
platform path. A shared `emptyDir` supplies the generated alteration scripts
directory at `/etc/logto/packages/cli/alteration-scripts` to both the bootstrap
and long-running core containers. Upstream's startup precondition deletes and
recreates those files on every boot, so the pod's `fsGroup: 10001` must keep that
mount writable for the non-root image. Bootstrap remains schema initialization,
not a credential check.
Upstream Logto `1.41.0` exposes 3001 and starts as `npm run start` from
`/etc/logto`, but declares no image `USER`. Felix must therefore package the
Aldehyde fork with numeric `USER 10001`; the chart enforces that same explicit
non-root contract and deliberately does not set Logto's root filesystem read-only
until the fork proves its writable-runtime requirements. The pinned unprivileged
Nginx filter does use a read-only root filesystem plus an `emptyDir` at `/tmp`.
The k3d runner proves chart installation with Garden-provided fixture Secrets;
fork-image startup behavior remains integration-tested by the external Aldehyde
fork repository.
