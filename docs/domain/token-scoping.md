# Provider-token scoping at the fleet-operator composition root

Status: accepted Phase 1 spike decision.

## Decision and sources

The ruled default is one Primordial `fleet-operator` Deployment, one process,
and one Kubernetes ServiceAccount. Its six real controllers are independently
enabled and receive controller-specific capability bundles constructed before
registration. Provider tokens are least-privilege tokens minted from the T4
root and are admitted only to the matching bundle.

This decision implements the following source requirements:

- `goals/dependency-operator.md:28-31`: one binary, six controller enables,
  controller-scoped tokens, and no controller holding another controller's
  credentials.
- `goals/dependency-operator.md:1176-1177`: the composition root wires exactly
  the tokens an enabled controller needs.
- `goals/dependency-operator.md:1231-1235`: the token-scoping mechanism must be
  decided and spiked before composition-root wiring lands.
- `T3-DESIGN.md:276`: one distribution runs the full set on Primordial and the
  dependency-only subset in Garden, with tokens scoped per controller.
- The controller's turn-006 reconciliation: one Primordial Deployment with
  construction-time capability bundles is design-conforming; escalation is
  required only if the spike concretely overturns it.

`BuildBundles(Config, CredentialSet)` is the executable spike. It is a pure,
deterministic constructor: it performs no I/O, parses no credential value, and
builds no vendor adapter. An enabled non-dependency controller must have its
complete named credential group. A disabled controller must have none of its
credential group. The dependency controller instead receives four explicit
optional doors, allowing Garden to derive or refuse at reconcile time.

## What the boundary proves

Capability bundles prove logical provider-token isolation. A controller's
registration and future reconcile path receives only the narrow provider doors
declared by its bundle. An enabled controller with incomplete required material
refuses startup. Credential material outside the enabled set also refuses
startup. Optional Garden doors are never nil: an unavailable door is a typed
`AbsentDoor` which returns a stable refusal instead of permitting a nil
dereference.

The dependency bundle is structurally Garden-safe. It has vendor/engine,
read-only-seed, broker-token, and native-Tigris doors and has no Infisical-write
or T4-root door. Broad Infisical-write or T4-root material is represented in the
input inventory only so an accidental mount can be rejected; it is never copied
into a bundle.

## What the boundary does not prove

The six Primordial controllers share one pod memory space. A compromise of the
process can compromise every credential wired into that process. They also
share one Kubernetes ServiceAccount and therefore one Kubernetes-RBAC boundary.
That boundary is the RBAC union required by every enabled controller, constrained
by the positive allowlist in the RBAC-minimality gate
(`scripts/validate/operator-rbac.sh`); it is not per-controller Kubernetes-RBAC
isolation.

Observe/active mode remains global. One `--observe` value applies to the whole
manager, and observe mode does not weaken or bypass the credential matrix. There
is no partial-observe controller configuration.

## Normative enable-by-credential matrix

| #   | Case                                                                                                                                                | Required outcome                                                                   |
| --- | --------------------------------------------------------------------------------------------------------------------------------------------------- | ---------------------------------------------------------------------------------- |
| 1   | A non-dependency controller is enabled and any required credential in its named group is absent.                                                    | Refuse startup and name the controller and missing credential.                     |
| 2   | Any credential group is supplied for a disabled controller.                                                                                         | Refuse startup as credential material outside the enabled set.                     |
| 3   | `EnableProblem=true`.                                                                                                                               | Refuse with the stable `problem sub-component not yet folded` reserved-seam error. |
| 4   | Garden dependency-only profile, with exactly the read-only-seed marker, broker token, and native Tigris key, or any subset of the dependency doors. | Accept; every omitted dependency door is an explicit typed `AbsentDoor`.           |
| 5   | Rotom/absol dependency-only profile with zero credentials.                                                                                          | Accept; derive-or-refuse is reconcile-time behavior.                               |
| 6   | Garden dependency-only profile plus Infisical-write material, a T4-root-path marker, or another controller's credential group.                      | Refuse startup.                                                                    |
| 7   | Full Primordial profile with all six real controllers enabled and all six controller groups complete.                                               | Accept; construct six distinct bundles, each exposing only its controller's doors. |
| 8   | Observe mode with any enable/credential combination.                                                                                                | Apply the same outcomes as active mode; observe changes no wiring legality.        |

Dependency is the intentional asymmetry in this matrix. Cluster, platform,
traffic, webhook, and cf-deploy are all-or-nothing at startup. Dependency has no
startup-required provider door because keyed Garden, partial Garden, and
zero-credential rotom/absol are all supported deployment shapes.

## Garden placement and late binding

The Garden dependency-only Deployment is a separate chart install of the same
binary with only the dependency controller enabled and only that profile's
allowed credential mounts. It is not another fleet control plane and never
receives another Primordial controller's credentials.

Per-controller ServiceAccounts and Deployments were evaluated and rejected here
because they change the already approved topology rather than implement its
provider-token boundary. Re-open that decision only if capability bundles
concretely cannot express an isolation the dependency-operator DoD requires.

The chart keeps controller enables and credential mounts independently
settable. A future authorized per-controller split can therefore be expressed as
a values/topology change without changing the credential inventory or CRD
schema.
