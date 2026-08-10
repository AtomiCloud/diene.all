# Core utilities

`@atomicloud/diene.core-utils` is the Bun family's small, deterministic value
layer. Import from the package root. It deliberately owns common normalization,
timing, collection, hashing, rooted filesystem, and C0 temporal-codec behavior;
configuration loading and deep merge belong to `@atomicloud/diene.config`.

The package dogfoods the published dependency pair
`@atomicloud/diene.result@1.0.2` and `@atomicloud/diene.interfaces@1.0.0`.
Fallible values use the former's async-native `Result<T, E>` rather than an
implicit throw path.

## Keys and simple utilities

`slugify(value)` applies NFKD normalization, removes combining marks, lowercases,
and produces a deterministic kebab-case value. Use it when a human label must
become an identifier, not for display text.

`namespacedKey(namespace, key)` composes the normalized parts as
`namespace:key`. It returns `Result<string, NamespacedKeyValidationError>`:
match the `ok` and `err` branches (or use a deliberate recovery), rather than
calling `unwrap` for ordinary validation. A namespace or key that normalizes to
empty is an `Err`, never a validation throw.

`sleep` is the explicit asynchronous delay primitive; `noop` is the intentional
no-operation callback. Keep delays out of ordinary unit tests. `fuzzyIncludes`
answers whether one string includes another case-insensitively; it is a search
aid, not a ranking, locale-collation, or authorization primitive.

## Collections, records, and stable values

Use `mapWithConcurrency` when independent asynchronous work needs a bounded
number of in-flight operations. Choose a limit that respects the downstream
resource, propagate mapper failures, and do not use it to create unbounded work.

`isRecord` distinguishes a plain record-shaped value from primitives, `null`, and
arrays before object access. `stableConfig` produces a deterministic,
configuration-safe representation suitable for repeatable comparisons or hash
inputs; it is not a replacement for schema validation. `unique` is the reusable
deduplication predicate for collection filtering.

`sha256` asynchronously creates a lowercase hexadecimal SHA-256 digest for a
UTF-8 string. Serialize a canonical value (for example, `JSON.stringify` of a
`stableConfig` result) when identities must be comparable; do not treat a digest
as encryption or as a substitute for verifying untrusted structured data.

## Rooted filesystem helpers

Filesystem helpers always receive an explicit root and resolve requested paths
below that root. In particular, use `safeJoin(root, ...)` and the related helpers
with an application-owned root such as a workspace or temporary directory. Never
let a helper infer `process.cwd()`, and reject/handle a path that escapes the
given root. This makes callers' filesystem authority visible and keeps tests
portable: exercise retained helpers against real temporary directories rather
than a global working directory.

## C0 wire-date codecs

The wire-date module translates between Temporal domain values and the C0
transport forms. It follows the repository's [date/time standard](../datetime/index.md)
and [C0 contracts standard](../contracts/README.md). These are wire values,
not locale display formats.

| Domain value         | Canonical wire form               |
| -------------------- | --------------------------------- |
| `Temporal.PlainDate` | date `YYYY-MM-DD`                 |
| `Temporal.PlainTime` | time `HH:mm:ss`                   |
| `Temporal.Instant`   | RFC3339 UTC instant ending in `Z` |
| `Temporal.Duration`  | ISO8601 duration                  |
| validated timezone   | IANA timezone identifier          |

Use the paired `parseWire*` and `formatWire*` functions at a transport boundary.
Parsing rejects non-canonical representations; formatting emits the one canonical
representation. Fractional instant seconds are preserved when present, while the
fixed `HH:mm:ss` time form rejects sub-second domain values rather than losing
precision. Preserve Temporal values inside the domain layer, serialize only at
the edge, and do not accept fixed offsets or abbreviations where an IANA zone
identifier is required.

## TestHelper and the meta tier

This package has **TestHelper=NO**. Its supported surface is a pure value library:
the slug, timing, fuzzy match, record, hash, unique, and wire codecs are cheap and
deterministic; rooted filesystem helpers receive their authority explicitly and
are verified against real temporary directories. There is no consumer-injected
port to fake and ordinary equality is sufficient for these values.

Accordingly, the inherited `pls test:meta` task remains a no-op and CI uploads no
empty `meta` Codecov flag. Across the library family, a real TestHelper's meta
tier proves three things: **assert-the-asserter** (each custom assertion accepts a
known-good case and rejects a known-bad one), **contract parity** (a fake and the
real implementation share behavior), and **fixture invariants** (builders and
fixtures cannot emit invalid values). Those checks become relevant here only if a
future consumer seam or repeated nontrivial assertion creates evidence that a
helper is useful.

See the shipped [usage skill](../../../skills/diene-core-utils-usage/SKILL.md)
for consumer patterns and the narrowly scoped procedure for revisiting that
decision.
