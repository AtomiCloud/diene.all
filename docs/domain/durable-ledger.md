# Durable ledger

The R2 durable ledger is the source of record for registered-fleet external
resources. It lives outside Kubernetes etcd in one L0, bootstrap-provisioned
S3-compatible bucket. The operator verifies that bucket exists and fails startup
loudly when it does not; it never creates or manages its own memory.

## Identity and schema

Every dependency entry is addressed by exactly six explicit segments:

```text
platform/landscape/class/module/vendor/account
```

All segments are mandatory, nonblank, and must not contain `/`. Account is an
opaque `ProviderAccount` name supplied by the caller and is never inferred from
platform, landscape, environment, credentials, or defaults. An external identity
is the composite `(vendor, account, externalId)` because an external ID is unique
only within its vendor account.

The additive entry schema contains:

- coordinate, phase, and external ID;
- duplicate vendor and account identity fields plus optional region;
- `secretPath`, which is only a pointer to secret storage;
- monotonic generation and canonical-JSON `lastAppliedHash`;
- UTC `createdAt`, `updatedAt`, `orphanedAt`, `tombstonedAt`, and `retainUntil`
  timestamps.

Timestamp strings are UTC RFC3339Nano and preserve fractional precision. Old
four-field JSON entries remain readable: missing additive fields decode to their
zero values and are backfilled when a later transition writes the entry.

The schema must never gain a field capable of holding a credential, password,
token, connection payload, or secret value. The unit tier pins the exact entry
field allowlist; secret material belongs in the referenced secret store only.
`lastAppliedHash` is produced by the published `coreutils.StableHash` function,
and the unhashed last-applied value is never persisted.

## State machine

Every operation validates the coordinate and performs its lookup before a state
change. Safe replay avoids another write.

| Operation         | Transition                                   | Replay                                   | Rejection                                               |
| ----------------- | -------------------------------------------- | ---------------------------------------- | ------------------------------------------------------- |
| Intent            | absent → intent                              | any existing entry is returned unchanged | invalid coordinate or intent                            |
| Adopt             | orphaned → created                           | intent, created, or confirmed unchanged  | missing, tombstoned, or unknown phase                   |
| Created           | intent → created                             | created or confirmed unchanged           | missing, orphaned, tombstoned, or unknown phase         |
| Confirm           | created → confirmed                          | confirmed unchanged                      | missing, intent, orphaned, tombstoned, or unknown phase |
| Orphan            | intent, created, or confirmed → orphaned     | missing or orphaned is a no-op           | tombstoned or unknown phase                             |
| AdvanceGeneration | stored generation N → greater N              | equal generation unchanged               | lower generation, missing, or tombstoned                |
| Tombstone         | created, confirmed, or orphaned → tombstoned | tombstoned unchanged                     | missing, intent, unknown phase, or incomplete proof     |
| Purge             | physical object removal                      | an absent object is success              | incomplete permit or unavailable purge capability       |

Strict services require an injected clock, stamp every mutation, reject impossible
transitions with typed `errors.Is`/`errors.As`-compatible errors, and enforce the
generation fence. Recovery resumes from each intermediate phase:

- intent resumes with Created then Confirm;
- created resumes with Confirm;
- orphaned resumes with Adopt then Confirm.

The inherited `NewService`, Get, Intent, Adopt, Created, Confirm, and Orphan facade
remains for existing fake-store consumers. It delegates to the same
engine, records no timestamp because the old constructor has no clock, and keeps
the historical leniency for out-of-order Created and Confirm calls. It does not
relax coordinate validation. New product paths use `NewStrictService` and
`IntentWithSpec`.

## Three deletion verbs

The three verbs are intentionally separate and are not interchangeable.

1. **CR deletion — orphan only.** The ledger row is retained and marked orphaned.
   Re-applying the coordinate adopts it back. This layer exposes no deletion path
   to a normal reconcile or finalizer.
2. **Spec edit removing a module — tombstone.** The caller first proves that a
   final backup snapshot was taken, the vendor resource was deleted, and the
   168-hour secret-retain intent was recorded. `NewTombstoneProof` requires all
   three assertions. Tombstone stamps `retainUntil = tombstonedAt + 168h`.
3. **Decommission — purge.** The caller first proves references clear, snapshot
   complete, externals deleted, and target authorization. `NewPurgePermit` requires
   all four assertions. Physical deletion additionally requires a service built
   with the separate `PurgeStore` capability.

Zero-value proof and permit values are invalid, and ordinary two-method `Store`
implementations have no purge method. The ledger does not perform snapshots,
vendor deletion, reference resolution, finalizer policy, or target authorization;
the owning controller supplies those proved facts.

## Object-store contract

`ledgerstore.MinioStore` maps a row to `prefix + coordinate.Key()` and stores
ordinary additive JSON with content type `application/json`.

- `VerifyBucket` calls `BucketExists`; absence returns `ErrBucketMissing` with the
  bucket name and bootstrap contract.
- Compatibility `EnsureBucket` is a deprecated delegate to `VerifyBucket` and
  never calls `MakeBucket`.
- missing objects read as `found=false`; transport and malformed-JSON errors are
  returned;
- `Put` writes a complete entry;
- `Purge` uses S3 object removal and exists only as the separate destructive
  capability.

The integration tier uses real MinIO. The harness creates the bucket as bootstrap,
then proves read/write, legacy-schema reads, nanosecond JSON round trips, corrupt
object failure, authorized and idempotent purge, absent-bucket failure, and that
verification never creates a bucket.

## Error contract

Domain callers classify errors with the exported categories
`ErrInvalidCoordinate`, `ErrInvalidIntent`, `ErrMissingEntry`,
`ErrInvalidTransition`, `ErrStaleGeneration`, `ErrInvalidTombstoneProof`,
`ErrInvalidPurgePermit`, `ErrPurgeUnavailable`, and `ErrInvalidTimestamp`.
`CoordinateError`, `TransitionError`, and `GenerationError` retain descriptive
field, phase, operation, coordinate, and generation context. Mapping these domain
errors to RFC 9457 problem catalog entries belongs at the API/manager boundary;
the pure ledger does not import a transport envelope.

## Follow-up integration seams

These surfaces are deliberately outside this foundation's ownership:

- the composition root should move from deprecated `EnsureBucket` to
  `VerifyBucket` and wire product controllers through `NewStrictService` with
  its clock instead of the lenient compatibility constructor;
- the local operator e2e harness must bootstrap the MinIO bucket before manager
  startup;
- the Garden dependency-only profile must be able to run without the Primordial
  R2 ledger, and the per-landscape ledger endpoint overlays must converge on the
  single L0 bucket contract;
- the shared operator-conventions finalizer paragraph must be reconciled with the
  governing stateful orphan/retain ruling.
