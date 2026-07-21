/// The shared, version-pinned C0 §1 temporal contract for the Dart family.
///
/// Downstream Dart-family packages import this surface and drive their own C0
/// conformance from the single [c0TemporalContract] value, rather than
/// redefining temporal cases:
///
/// ```dart
/// import 'package:diene_core_utils/c0_temporal.dart';
/// ```
library;

export 'src/c0_temporal_contract.dart';
