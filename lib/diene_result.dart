/// Sealed [Result] and [Option] values with C0-compatible wire codecs.
library;

export 'src/option.dart';
export 'src/problem.dart';
export 'src/result.dart';
export 'src/unwrap_error.dart';
export 'src/wire.dart' show OptionSerial, ResultSerial;
