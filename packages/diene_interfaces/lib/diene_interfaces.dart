/// Shared, implementation-free process, filesystem, terminal, logging, and
/// metrics seams for the Dart family (S33 common interfaces).
///
/// Every fallible member returns `Result` from `package:diene_result` and never
/// throws to communicate an expected failure. The failure channel is the
/// canonical `Problem` envelope from `package:diene_problems`, minted through
/// the single C0 §2 type-URI builder.
///
/// This library owns NO trace seam (RB-19) and NO OTel implementer: Dart and
/// Flutter telemetry rides Faro at runtime through the frontend machinery.
/// In-memory fakes for all five seams ship in
/// `package:diene_interfaces/test_helper.dart`.
library;

export 'src/logging.dart';
export 'src/metrics.dart';
export 'src/port_problem.dart';
export 'src/system.dart';
export 'src/telemetry.dart';
export 'src/terminal.dart';
export 'src/vfs.dart';
