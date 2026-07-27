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

All five segments are mandatory and must be single path segments. The resolver
derives and returns this pointer only; it never reads, accepts, stores, logs, or
returns a credential value. Per-account onboarding and quota checks are Phase 3
adapter work; this pure package defines only their result shape.
