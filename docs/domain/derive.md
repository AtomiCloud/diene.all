# Deterministic external-name derivation

`lib/operator/derive` is the single pure naming primitive for external
resources. It derives a name from the complete LPSM coordinate:
`landscape`, `platform`, `service`, and `module`. `ForkName` adds the literal
`fork`, the Garden instance, and a non-negative generation. This package does
not derive DNS A-sets, edge documents, delivery maps, or any controller-specific
resource identity.

## Caller-owned profile

Every call supplies a `derive.Profile`, so the caller records the external
system's normalization and byte-length contract rather than relying on an
implicit global convention. A profile supplies:

- `Normalize`, a function that maps one segment into the vendor's accepted
  charset;
- `MaxLength`, the UTF-8 byte budget;
- `Separator`, the caller's readable segment separator;
- `DigestLength`, the number of lower-case base32 SHA-256 characters retained;
  each character supplies five bits of collision resistance; and
- `Overflow`, either `reject` or `trim-with-digest`.

The package does not lowercase, replace characters, or otherwise impose a
vendor charset itself. A blank raw segment, a normalizer error, a blank
normalized result, or invalid UTF-8 is rejected with a typed error. Profiles
that cannot fit one readable byte, their separator, and their declared digest
are rejected before any name is emitted.

## Exact name and collision rule

Each input is first normalized independently. The readable body joins those
normalized values with `Separator`. The name always ends in
`Separator + digest`, where `digest` is the first `DigestLength` lower-case
base32 characters of SHA-256 over a length-framed `derive/v1` preimage. The
preimage contains every raw field name, byte length, and byte value; fork names
also contain the literal fork marker, instance, and decimal generation. Thus
two coordinates that normalize to the same readable body retain different hash
inputs.

If the complete readable body plus suffix fits `MaxLength`, it is emitted as
is. With `OverflowReject`, a longer output returns `ErrNameTooLong`. With the
explicit `OverflowTrim` rule, only the readable body is shortened at a UTF-8
boundary; the separator and full declared digest suffix are retained. There is
no silent truncation or unrecorded hash policy.

SHA-256 is finite, so the API promises collision resistance within the caller's
declared digest budget rather than an impossible absolute guarantee. A profile
with `n` digest characters has `5n` digest bits; callers choose that budget for
their resource count and collision risk. The full raw-coordinate preimage,
mandatory suffix, and explicit overflow rule ensure that normalized or trimmed
readable portions never become the identity on their own.

## Errors

All failures are `*derive.Error` and support `errors.Is` with the exported
`derive.ErrorKind` values: `ErrInvalidProfile`, `ErrBlankSegment`,
`ErrUnnormalizable`, `ErrNameTooLong`, and `ErrInvalidGeneration`. A normalizer
error is available through `errors.Unwrap` as well. Callers can therefore make
configuration and reconciliation refusal decisions without parsing strings.
