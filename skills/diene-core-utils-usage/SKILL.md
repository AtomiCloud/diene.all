---
name: diene-core-utils-usage
description: Use diene_core_utils for canonical keys, config merge/coercion, sleep, and C0 temporal wire forms.
---

# Diene core-utils usage

Import `package:diene_core_utils/diene_core_utils.dart`. Use `slugify` and match
both branches of `namespacedKey`; never unwrap by throwing. Apply configuration as
`deepMerge(base, overlay)` and build env overlays with an explicit prefix through
`environmentToNestedMap`; lists use `__0`, `__1`, never JSON or commas.

Use `WireCodec`/wire value types at service boundaries. Keep locale display formats
outside this package; instants must end in `Z` and timezones must be IANA ids.

This package has TestHelper=NO. Do not invent one for convenient fixtures. If a
future consumer must fake a newly introduced seam or repeats a genuinely nontrivial
assertion, follow `doc/core_utils.md#testhelper-and-meta-tier`
exactly: dependency-light `lib/test_helper.dart`, no test-framework runtime deps,
assert-the-asserter/contract-parity/invariant meta tests, helper-only coverage, and
conditional `meta` upload.
