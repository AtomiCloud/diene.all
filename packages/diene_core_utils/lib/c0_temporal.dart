/// The shared, version-pinned C0 §1 temporal contract for the Dart family.
///
/// `diene_core_utils` OWNS this contract. Downstream Dart-family packages
/// (`config`, `problems`, `auth-engine`, `api-engine`, `e2e`, `interfaces`)
/// import THIS sub-library and drive their own C0 conformance from the single
/// `c0TemporalContract` value, instead of each redefining temporal cases that
/// would then drift apart:
///
/// ```dart
/// import 'package:diene_core_utils/c0_temporal.dart';
///
/// for (final String valid in c0TemporalContract.dates.valid) {
///   // assert your own date surface accepts it
/// }
/// ```
///
/// The contract's provenance pins both the C0 source document and the official
/// IANA release its timezone identifiers derive from, so a conformance proof
/// never reads host IANA data or the host clock: timezone and instant vectors
/// are injected from the contract itself.
library;

export 'src/c0_temporal_contract.dart';
