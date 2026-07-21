---
name: carbon
description: Use when changing Carbon platform charts, its platform-name scaffold, dependency declarations, or validation and publishing machinery.
---

Read [the Carbon baseline](../../../docs/developer/carbon-baseline.md) and the linked
Helm, service-tree, validation, testing, secrets, and release standards before editing
this surface.

Keep the ownership split explicit: the application chart owns the namespace,
folder-prefixed token `ExternalSecret`, and namespaced platform `SecretStore`; the
primordial chart owns only platform-shared `PlatformDependency` declarations.

Run `scripts/ci/carbon.sh` for host-safe verification. Do not run the k3d harness
without explicit proof authorization.
