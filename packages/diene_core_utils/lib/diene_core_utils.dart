/// Pure Dart utilities shared by the Diene Dart family.
///
/// Three groups of members, all total:
///
/// - **Identity** — [slugify] and [namespacedKey] turn arbitrary human text into
///   deterministic kebab-case slugs and `namespace:key` identifiers.
/// - **Configuration** — [deepMerge]/[deepMergeAll], [coerceEnvironmentScalar],
///   [environmentToNestedMap], and [stableConfig] implement the C0 §3 layering,
///   case-insensitive key matching, indexed-list, and blank-is-unset rules.
/// - **C0 temporal wire forms** — [WireDate], [WireTime], [IsoDuration],
///   [IanaTimezone], [parseRfc3339Utc]/[formatRfc3339Utc], and the [WireCodec]
///   facade implement the C0 §1 ISO 8601 / RFC 3339 and IANA timezone contract,
///   which exists to kill bespoke date formats.
///
/// Every fallible member returns `Result` from `package:diene_result` with the
/// canonical `Problem` envelope from `package:diene_problems` as its error
/// channel; nothing in this library throws to report an expected failure. The
/// only members that touch the outside world do so through the INJECTED `Vfs`
/// interface from `package:diene_interfaces` — this package imports neither
/// `dart:io` nor Flutter, so it runs unchanged on the VM and on the web.
///
/// The shared, version-pinned C0 §1 temporal contract is exported separately
/// from `package:diene_core_utils/c0_temporal.dart` so downstream Dart-family
/// packages can drive their own conformance from one value.
library;

export 'src/c0_temporal_contract.dart';
export 'src/coercion.dart';
export 'src/concurrency.dart';
export 'src/iana_zones.dart';
export 'src/merge.dart';
export 'src/record.dart';
export 'src/slug.dart';
export 'src/text.dart';
export 'src/timing.dart';
export 'src/util_problem.dart';
export 'src/vfs_config.dart';
export 'src/wire.dart';
