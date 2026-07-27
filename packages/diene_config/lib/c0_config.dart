/// The version-pinned C0 §3 Config contract, as a separately exported
/// sub-library.
///
/// Downstream Dart-family packages that need the SAME release identity — to
/// prove their own config conformance against the same frozen vectors — import
/// this instead of restating the release id and digest:
///
/// ```dart
/// import 'package:diene_config/c0_config.dart';
///
/// expect(c0ConfigContract.provenance.releaseId, 'c0-fixtures-r2');
/// ```
///
/// It is exported from the main barrel too, so a consumer that already imports
/// `package:diene_config/diene_config.dart` needs nothing extra. The separate
/// entrypoint mirrors `package:diene_core_utils/c0_temporal.dart` and exists so
/// a conformance-only consumer can take the contract without the loader.
library;

export 'src/c0_config_contract.dart';
