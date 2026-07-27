# Provider accounts

`ProviderAccount` is a schema-only registry. Carbon's primordial chart writes
one registry CR for each named provider account; dependency-operator is the
read-only consumer at reconcile time. The dependency operator has no
`ProviderAccount` reconciler, onboarding adapter, provider client, RBAC writer,
or status writer in this boundary.

## Explicit selection

Each dependency module selects an account explicitly with `account: {name}`.
The selected vendor and account name identify exactly one registry entry. There
is no vendor default, landscape/tier inference, or fallback selection. Missing
selectors, missing named accounts, and duplicate matches are strict `Unresolved`
refusals so the future controller can publish a condition instead of guessing.

Registry entries must satisfy both forms of the identity law:

- an account name is unique within its vendor;
- the `(vendor, name)` identity occurs at most once across the rendered fleet
  registry.

The same account name may therefore be used by different vendors, but the same
vendor/name pair may not be rendered twice.

## Credential pointers

Account credentials are addressed only by the S10 logical pointer:

```text
/{platform}/{landscape}/{class}/{vendor}-account-{name}
```

All five inputs are mandatory. The resolver derives and returns this pointer
only; it never reads, accepts, stores, logs, or returns a credential value.
Per-account onboarding and quota checks are Phase 3 adapter work; this pure
package defines only their result shape.

### Safe-segment grammar

Every input segment (platform, landscape, class, vendor, and name) and every
account identity field is validated against the committed `ProviderAccount`
vendor/name domain. The grammar is strict and reject-only: nothing is trimmed,
case-folded, user-escaped, or otherwise normalized.

A valid segment:

- is 1–63 bytes long;
- starts and ends with a lowercase ASCII letter or digit; and
- otherwise contains only lowercase ASCII letters (`a`–`z`), digits (`0`–`9`),
  and hyphens (`-`).

This is the full CRD pattern
`^[a-z0-9]([-a-z0-9]*[a-z0-9])?$`, including valid spellings such as `account`,
`account-prod`, and `a-account-b`. Slash, backslash, dot/dot-dot, percent or
user escape syntax, whitespace, Unicode, uppercase, empty, leading/trailing
hyphen, and overlength forms are refused rather than normalized.

The same grammar drives selector resolution (`ErrInvalidSelector`), registry
validation (`ErrInvalidRegistry`), and pointer construction
(`ErrInvalidCredentialPointer`); all three are
[`errors.Is`](https://pkg.go.dev/errors#Is)-compatible under their existing
invalid category, and account-identity and pointer validation therefore cannot
disagree.

### Compatible, reversible identity mapping

For each accepted `(vendor, name)`, the resolver first builds the established
S10 final component `{vendor}-account-{name}`. It examines every `-account-`
position and counts only decompositions whose two sides are themselves valid
1–63 byte identity labels:

- when there is exactly one valid decomposition, the established component is
  retained byte-for-byte;
- when there is more than one valid decomposition, the component is
  `_pa_{vendor}_{name}`.

The escaped form is deterministic and reversible: underscore is outside the
input schema, so an escaped component cannot collide with any raw S10 component
and neither identity can contain the separator. Strip `_pa_` and split once at
the remaining underscore to recover the exact vendor and name. No identity is
silently normalized. The mapping therefore yields, for example:

| Vendor        | Name           | Final component             |
| ------------- | -------------- | --------------------------- |
| `neon`        | `production-a` | `neon-account-production-a` |
| `account`     | `prod`         | `account-account-prod`      |
| `neon`        | `account-prod` | `_pa_neon_account-prod`     |
| `a`           | `b-account-c`  | `_pa_a_b-account-c`         |
| `a-account-b` | `c`            | `_pa_a-account-b_c`         |

The last two identities previously collapsed onto the same raw component;
their escaped components are distinct. A delimiter-shaped substring does not
by itself force escaping when its alternate side would be non-schema (for
example, ending in a hyphen or exceeding 63 bytes), which preserves every
already-unambiguous S10 path.

### Producer/consumer compatibility and migration risk

Carbon writes the literal Infisical folder and dependency-operator reads it, so
both producer and consumer must derive this same mapping from the same
vendor/name pair. Ordinary, unambiguous accounts retain their exact existing
folder and require no migration. An ambiguous account instead requires the
producer and its credential material to move to the escaped component before
the consumer can read it.

This pure package neither writes folders nor migrates credentials. A legacy raw
ambiguous folder cannot be adopted or used as a fallback safely because the raw
name does not identify which of multiple valid accounts owns it. Rollout must
therefore coordinate the carbon-side mapping and explicit credential
copy/recreation with the dependency-operator version. Until that is complete,
an ambiguous account can remain unresolved due to a missing escaped folder;
mixed producer/consumer versions carry the same risk. The resolver deliberately
does not guess, alias the raw collision, or define an automatic migration
policy.
