# Lithium distribution

This repository publishes one semver for the Aldehyde Logto fork image reference
and the `diene-lithium` / `diene-lithium-primordial` OCI chart pair. Release
stamping requires both chart versions, both app versions, and `image.tag` to match.
The app chart is a
read-only consumer of the boot material minted by logto-operator; it never writes
Infisical or creates a credential.

`FLEET` derives `api.lithium.<platform>.<vlandscape>.cluster.atomi.cloud`, exposes
the core endpoint through a LoadBalancer, consumes a database URL and the exact
`/{platform}/lithium` boot pair using ExternalSecrets, and has no private service
path. The primordial chart emits one database `PlatformDependency` per vlandscape
and one `VirtualLandscapeService` per serving row.

`GARDEN-LOCAL` derives
`api.lithium.<platform>.<instance>.<landscape>.<zone>`, uses direct local Secret
references, and emits local core and management Services only. It has lifecycle
labels for Garden instance UID and allocation generation. Hosted profiles leave
their edge, certificate, and Boron ownership to ENTEI.

The k3d runner proves chart installation with Garden-provided fixture Secrets. It
does not claim fork-image startup behavior; that image is owned and integration
tested by the external Aldehyde fork repository.
