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

All five segments are mandatory. The resolver derives and returns this pointer
only; it never reads, accepts, stores, logs, or returns a credential value.
Per-account onboarding and quota checks are Phase 3 adapter work; this pure
package defines only their result shape.

### Safe-segment grammar

Because carbon writes this pointer as a literal Infisical folder path and
dependency-operator reads back the exact same string, the pointer is **not**
re-encoded — the canonical inputs are preserved byte-for-byte. Instead every
segment (platform, landscape, class, vendor, name) and every account identity
field is validated against one strict, reject-only grammar. Nothing is silently
normalized: an input that is not already canonical is refused, so two distinct
identities can never be folded onto one accepted pointer.

A valid segment:

- is nonblank — neither empty nor whitespace-only;
- contains **only** lowercase ASCII letters (`a`–`z`), digits (`0`–`9`), and
  the hyphen (`-`). This single character rule rejects, together, every
  reserved or ambiguous form: the path separator `/` and the backslash alias
  `\`, the path-special `.` and `..` components, percent/escape sequences such
  as `%2e`/`%2f`, any Unicode whitespace, and uppercase input. Uppercase is
  **rejected, never case-folded**, so `Neon` and `neon` cannot canonicalize
  onto the same pointer;
- must **not** contain the reserved delimiter token `account`.

The same grammar drives selector resolution (`ErrInvalidSelector`), registry
validation (`ErrInvalidRegistry`), and pointer construction
(`ErrInvalidCredentialPointer`); all three are
[`errors.Is`](https://pkg.go.dev/errors#Is)-compatible under their existing
invalid category, and account-identity and pointer validation therefore cannot
disagree.

### Why the pointer is unambiguous

The final component is built as `{vendor}-account-{name}`. Because neither
vendor nor name may contain the token `account`, and the delimiter's
surrounding `-` cannot be part of an `account` run (that token has no hyphen),
the `-account-` the constructor inserts is the **only** occurrence of `account`
in the component. The component therefore decomposes to exactly one
`(vendor, name)` pair. The two witness identities from the review —
`vendor="a", name="b-account-c"` and `vendor="a-account-b", name="c"` — both
contain the reserved token and are rejected outright, so they can never resolve
to a shared `/…/a-account-b-account-c` pointer. Traversal-form components (`.`,
`..`, `/`, `\`) are impossible for the same reason: their characters are outside
the grammar.
