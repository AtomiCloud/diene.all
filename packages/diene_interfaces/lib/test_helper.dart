/// Dependency-light in-memory implementations of every `diene_interfaces` seam.
///
/// This sub-library deliberately depends on NO test framework, matcher library,
/// mocking package, Flutter, or exporter — only on the seams themselves,
/// `diene_result`, and `diene_problems`. It therefore adds nothing to a
/// consumer's production dependency graph (family DEPENDENCY-LIGHT rule).
///
/// Every fake is stateful and deterministic, and every fallible member accepts
/// FIFO *scripted* results so a consumer can exercise failure paths without a
/// mocking framework and without exceptions.
library;

import 'dart:collection';
import 'dart:convert';

import 'package:diene_problems/diene_problems.dart';
import 'package:diene_result/diene_result.dart';

import 'diene_interfaces.dart';

/// A deterministic [System] with mutable in-memory process state.
final class InMemorySystem implements System {
  /// Creates a system fake seeded with [environment], [directory], and [now].
  InMemorySystem({
    Map<String, String> environment = const <String, String>{},
    this.directory = '/',
    DateTime? now,
  }) : environmentVariables = Map<String, String>.of(environment),
       now = (now ?? DateTime.fromMillisecondsSinceEpoch(0, isUtc: true))
           .toUtc();

  /// Mutable environment the fake answers from.
  final Map<String, String> environmentVariables;

  /// Every duration passed to [delay], in call order.
  final List<Duration> requestedDelays = <Duration>[];

  final Queue<Result<String?>> _environmentResults = Queue<Result<String?>>();
  final Queue<Result<String>> _directoryResults = Queue<Result<String>>();
  final Queue<Result<DateTime>> _clockResults = Queue<Result<DateTime>>();
  final Queue<Result<void>> _delayResults = Queue<Result<void>>();

  /// Working directory the fake answers from.
  String directory;

  /// Instant the fake's clock answers with.
  DateTime now;

  /// Scripts the next [environment] answer.
  void enqueueEnvironmentResult(Result<String?> result) {
    _environmentResults.add(result);
  }

  /// Scripts the next [currentDirectory] answer.
  void enqueueDirectoryResult(Result<String> result) {
    _directoryResults.add(result);
  }

  /// Scripts the next [nowUtc] answer.
  void enqueueClockResult(Result<DateTime> result) {
    _clockResults.add(result);
  }

  /// Scripts the next [delay] answer.
  void enqueueDelayResult(Result<void> result) {
    _delayResults.add(result);
  }

  @override
  Result<String?> environment(String name) => _environmentResults.isNotEmpty
      ? _environmentResults.removeFirst()
      : Ok<String?>(environmentVariables[name]);

  @override
  Result<String> currentDirectory() => _directoryResults.isNotEmpty
      ? _directoryResults.removeFirst()
      : Ok<String>(directory);

  @override
  Result<DateTime> nowUtc() => _clockResults.isNotEmpty
      ? _clockResults.removeFirst()
      : Ok<DateTime>(now.toUtc());

  @override
  Future<Result<void>> delay(Duration duration) async {
    requestedDelays.add(duration);
    return _delayResults.isNotEmpty
        ? _delayResults.removeFirst()
        : const Ok<void>(null);
  }
}

/// A stateful, byte-backed [Vfs].
///
/// Scripted results are FIFO and short-circuit the corresponding operation,
/// which supports deterministic fault injection without a mocking framework.
final class InMemoryVfs implements Vfs {
  /// Creates a filesystem fake seeded with [files] and [directories].
  InMemoryVfs({
    Map<String, List<int>> files = const <String, List<int>>{},
    Iterable<String> directories = const <String>['/'],
    DateTime? modifiedAt,
  }) : _files = <String, List<int>>{
         for (final MapEntry<String, List<int>> entry in files.entries)
           normalizePath(entry.key): List<int>.of(entry.value),
       },
       _directories = <String>{
         '/',
         for (final String directory in directories) normalizePath(directory),
       },
       modifiedAt =
           (modifiedAt ?? DateTime.fromMillisecondsSinceEpoch(0, isUtc: true))
               .toUtc() {
    for (final String path in _files.keys.toList()) {
      _createParents(_parent(path));
    }
  }

  final Map<String, List<int>> _files;
  final Set<String> _directories;
  final Queue<Result<bool>> _existsResults = Queue<Result<bool>>();
  final Queue<Result<VfsStat>> _statResults = Queue<Result<VfsStat>>();
  final Queue<Result<List<int>>> _readBytesResults = Queue<Result<List<int>>>();
  final Queue<Result<String>> _readTextResults = Queue<Result<String>>();
  final Queue<Result<void>> _writeBytesResults = Queue<Result<void>>();
  final Queue<Result<void>> _writeTextResults = Queue<Result<void>>();
  final Queue<Result<List<VfsEntry>>> _listResults =
      Queue<Result<List<VfsEntry>>>();
  final Queue<Result<void>> _createDirectoryResults = Queue<Result<void>>();
  final Queue<Result<void>> _deleteResults = Queue<Result<void>>();

  /// Modified instant reported for every entry.
  final DateTime modifiedAt;

  /// Snapshot of the stored files, deeply unmodifiable.
  Map<String, List<int>> get files =>
      UnmodifiableMapView<String, List<int>>(<String, List<int>>{
        for (final MapEntry<String, List<int>> entry in _files.entries)
          entry.key: List<int>.unmodifiable(entry.value),
      });

  /// Snapshot of the stored directories.
  Set<String> get directories => Set<String>.unmodifiable(_directories);

  /// Scripts the next [exists] answer.
  void enqueueExistsResult(Result<bool> result) => _existsResults.add(result);

  /// Scripts the next [stat] answer.
  void enqueueStatResult(Result<VfsStat> result) => _statResults.add(result);

  /// Scripts the next [readBytes] answer.
  void enqueueReadBytesResult(Result<List<int>> result) {
    _readBytesResults.add(result);
  }

  /// Scripts the next [readText] answer.
  void enqueueReadTextResult(Result<String> result) {
    _readTextResults.add(result);
  }

  /// Scripts the next [writeBytes] answer.
  void enqueueWriteBytesResult(Result<void> result) {
    _writeBytesResults.add(result);
  }

  /// Scripts the next [writeText] answer.
  void enqueueWriteTextResult(Result<void> result) {
    _writeTextResults.add(result);
  }

  /// Scripts the next [list] answer.
  void enqueueListResult(Result<List<VfsEntry>> result) {
    _listResults.add(result);
  }

  /// Scripts the next [createDirectory] answer.
  void enqueueCreateDirectoryResult(Result<void> result) {
    _createDirectoryResults.add(result);
  }

  /// Scripts the next [delete] answer.
  void enqueueDeleteResult(Result<void> result) {
    _deleteResults.add(result);
  }

  @override
  Future<Result<bool>> exists(String path) async {
    if (_existsResults.isNotEmpty) {
      return _existsResults.removeFirst();
    }
    final String normalized = normalizePath(path);
    return Ok<bool>(
      _files.containsKey(normalized) || _directories.contains(normalized),
    );
  }

  @override
  Future<Result<VfsStat>> stat(String path) async {
    if (_statResults.isNotEmpty) {
      return _statResults.removeFirst();
    }
    final String normalized = normalizePath(path);
    final List<int>? bytes = _files[normalized];
    if (bytes != null) {
      return Ok<VfsStat>(
        VfsStat(
          type: VfsEntryType.file,
          size: bytes.length,
          modifiedAt: modifiedAt,
        ),
      );
    }
    if (_directories.contains(normalized)) {
      return Ok<VfsStat>(
        VfsStat(type: VfsEntryType.directory, size: 0, modifiedAt: modifiedAt),
      );
    }
    return _notFound<VfsStat>('stat', normalized);
  }

  @override
  Future<Result<List<int>>> readBytes(String path) async {
    if (_readBytesResults.isNotEmpty) {
      return _readBytesResults.removeFirst();
    }
    final String normalized = normalizePath(path);
    final List<int>? bytes = _files[normalized];
    return bytes == null
        ? _notFound<List<int>>('readBytes', normalized)
        : Ok<List<int>>(List<int>.unmodifiable(bytes));
  }

  @override
  Future<Result<String>> readText(String path) async {
    if (_readTextResults.isNotEmpty) {
      return _readTextResults.removeFirst();
    }
    final String normalized = normalizePath(path);
    final List<int>? bytes = _files[normalized];
    return bytes == null
        ? _notFound<String>('readText', normalized)
        : Ok<String>(utf8.decode(bytes, allowMalformed: true));
  }

  @override
  Future<Result<void>> writeBytes(
    String path,
    List<int> bytes, {
    bool createParents = false,
  }) async {
    if (_writeBytesResults.isNotEmpty) {
      return _writeBytesResults.removeFirst();
    }
    return _write('writeBytes', path, bytes, createParents: createParents);
  }

  @override
  Future<Result<void>> writeText(
    String path,
    String content, {
    bool createParents = false,
  }) async {
    if (_writeTextResults.isNotEmpty) {
      return _writeTextResults.removeFirst();
    }
    return _write(
      'writeText',
      path,
      utf8.encode(content),
      createParents: createParents,
    );
  }

  @override
  Future<Result<List<VfsEntry>>> list(
    String path, {
    bool recursive = false,
  }) async {
    if (_listResults.isNotEmpty) {
      return _listResults.removeFirst();
    }
    final String normalized = normalizePath(path);
    if (!_directories.contains(normalized)) {
      return _notFound<List<VfsEntry>>('list', normalized);
    }
    final String prefix = normalized == '/' ? '/' : '$normalized/';
    final List<VfsEntry> entries = <VfsEntry>[
      for (final String directory in _directories)
        if (directory != normalized &&
            directory.startsWith(prefix) &&
            (recursive || !_relative(directory, prefix).contains('/')))
          VfsEntry(
            path: directory,
            type: VfsEntryType.directory,
            size: 0,
            modifiedAt: modifiedAt,
          ),
      for (final MapEntry<String, List<int>> file in _files.entries)
        if (file.key.startsWith(prefix) &&
            (recursive || !_relative(file.key, prefix).contains('/')))
          VfsEntry(
            path: file.key,
            type: VfsEntryType.file,
            size: file.value.length,
            modifiedAt: modifiedAt,
          ),
    ]..sort((VfsEntry left, VfsEntry right) => left.path.compareTo(right.path));
    return Ok<List<VfsEntry>>(List<VfsEntry>.unmodifiable(entries));
  }

  @override
  Future<Result<void>> createDirectory(
    String path, {
    bool recursive = false,
  }) async {
    if (_createDirectoryResults.isNotEmpty) {
      return _createDirectoryResults.removeFirst();
    }
    final String normalized = normalizePath(path);
    final String parent = _parent(normalized);
    if (!_directories.contains(parent) && !recursive) {
      return _notFound<void>('createDirectory', parent);
    }
    if (recursive) {
      _createParents(normalized);
    } else {
      _directories.add(normalized);
    }
    return const Ok<void>(null);
  }

  @override
  Future<Result<void>> delete(String path, {bool recursive = false}) async {
    if (_deleteResults.isNotEmpty) {
      return _deleteResults.removeFirst();
    }
    final String normalized = normalizePath(path);
    if (_files.remove(normalized) != null) {
      return const Ok<void>(null);
    }
    if (!_directories.contains(normalized)) {
      return _notFound<void>('delete', normalized);
    }
    final String prefix = normalized == '/' ? '/' : '$normalized/';
    final bool hasChildren =
        _files.keys.any((String key) => key.startsWith(prefix)) ||
        _directories.any(
          (String directory) =>
              directory != normalized && directory.startsWith(prefix),
        );
    if (hasChildren && !recursive) {
      return portFailure<void>(
        port: PortName.vfs,
        code: PortErrorCode.directoryNotEmpty,
        operation: 'delete',
        message: 'Directory not empty',
        details: <String, Object?>{'path': normalized},
      );
    }
    _files.removeWhere((String key, List<int> _) => key.startsWith(prefix));
    _directories.removeWhere(
      (String directory) =>
          directory == normalized || directory.startsWith(prefix),
    );
    _directories.add('/');
    return const Ok<void>(null);
  }

  Result<void> _write(
    String operation,
    String path,
    List<int> bytes, {
    required bool createParents,
  }) {
    final String normalized = normalizePath(path);
    final String parent = _parent(normalized);
    if (!_directories.contains(parent)) {
      if (!createParents) {
        return _notFound<void>(operation, parent);
      }
      _createParents(parent);
    }
    _files[normalized] = List<int>.of(bytes);
    return const Ok<void>(null);
  }

  void _createParents(String path) {
    if (path == '/') {
      _directories.add('/');
      return;
    }
    final List<String> segments = path.split('/')
      ..removeWhere((String segment) => segment.isEmpty);
    String current = '';
    for (final String segment in segments) {
      current = '$current/$segment';
      _directories.add(current);
    }
  }

  Err<T> _notFound<T>(String operation, String path) => portFailure<T>(
    port: PortName.vfs,
    code: PortErrorCode.notFound,
    operation: operation,
    message: 'Path not found',
    details: <String, Object?>{'path': path},
  );

  static String _relative(String path, String prefix) =>
      path.substring(prefix.length);

  static String _parent(String path) {
    final int separator = path.lastIndexOf('/');
    return separator <= 0 ? '/' : path.substring(0, separator);
  }

  /// Collapses empty segments and forces a leading slash.
  ///
  /// The real `Vfs` contract leaves normalisation to implementations; this fake
  /// declares its own rule so consumer tests are deterministic.
  static String normalizePath(String path) {
    final Iterable<String> segments = path
        .split('/')
        .where((String part) => part.isNotEmpty);
    return '/${segments.join('/')}';
  }
}

/// A FIFO-scripted [Terminal] that records every command, write, and read.
final class InMemoryTerminal implements Terminal {
  /// Creates a terminal fake.
  InMemoryTerminal({
    this.interactive = true,
    List<String> input = const <String>[],
  }) : _input = Queue<String>.of(input);

  /// Every invocation passed to [run], in call order.
  final List<TerminalCommand> commands = <TerminalCommand>[];

  /// Every write passed to [write], in call order.
  final List<TerminalWrite> writes = <TerminalWrite>[];

  /// Every read request passed to [readLine], in call order.
  final List<TerminalRead> reads = <TerminalRead>[];

  final Queue<String> _input;
  final Queue<Result<TerminalOutput>> _results =
      Queue<Result<TerminalOutput>>();
  final Queue<Result<void>> _writeResults = Queue<Result<void>>();
  final Queue<Result<String?>> _readResults = Queue<Result<String?>>();

  @override
  final bool interactive;

  /// Scripts the next [run] answer.
  void enqueue(Result<TerminalOutput> result) => _results.add(result);

  /// Scripts the next [write] answer.
  void enqueueWriteResult(Result<void> result) => _writeResults.add(result);

  /// Scripts the next [readLine] answer.
  void enqueueReadResult(Result<String?> result) => _readResults.add(result);

  @override
  Future<Result<TerminalOutput>> run(TerminalCommand command) async {
    commands.add(command);
    return _results.isEmpty
        ? portFailure<TerminalOutput>(
            port: PortName.terminal,
            code: PortErrorCode.unexpectedCall,
            operation: 'run',
            message: 'Terminal result not scripted',
            details: <String, Object?>{'executable': command.executable},
          )
        : _results.removeFirst();
  }

  @override
  Future<Result<void>> write(TerminalWrite output) async {
    writes.add(output);
    return _writeResults.isNotEmpty
        ? _writeResults.removeFirst()
        : const Ok<void>(null);
  }

  @override
  Future<Result<String?>> readLine([
    TerminalRead input = const TerminalRead(),
  ]) async {
    reads.add(input);
    if (_readResults.isNotEmpty) {
      return _readResults.removeFirst();
    }
    return Ok<String?>(_input.isEmpty ? null : _input.removeFirst());
  }
}

/// An in-memory [LoggerSink] with FIFO fault injection.
final class InMemoryLoggerSink implements LoggerSink {
  /// Every record accepted by [emit], in call order.
  final List<LogRecord> records = <LogRecord>[];

  final Queue<Result<void>> _results = Queue<Result<void>>();
  final Queue<Result<void>> _flushResults = Queue<Result<void>>();

  /// How many times [flush] was called.
  int flushCount = 0;

  /// Scripts the next [emit] answer.
  void enqueue(Result<void> result) => _results.add(result);

  /// Scripts the next [flush] answer.
  void enqueueFlushResult(Result<void> result) => _flushResults.add(result);

  @override
  Result<void> emit(LogRecord record) {
    if (_results.isNotEmpty) {
      return _results.removeFirst();
    }
    records.add(record);
    return const Ok<void>(null);
  }

  @override
  Future<Result<void>> flush() async {
    flushCount += 1;
    return _flushResults.isNotEmpty
        ? _flushResults.removeFirst()
        : const Ok<void>(null);
  }
}

/// An in-memory [MetricsCollector] with FIFO fault injection.
final class InMemoryMetricsCollector implements MetricsCollector {
  /// Every sample accepted by [emit], in call order.
  final List<MetricRecord> records = <MetricRecord>[];

  final Queue<Result<void>> _results = Queue<Result<void>>();
  final Queue<Result<void>> _flushResults = Queue<Result<void>>();

  /// How many times [flush] was called.
  int flushCount = 0;

  /// Scripts the next [emit] answer.
  void enqueue(Result<void> result) => _results.add(result);

  /// Scripts the next [flush] answer.
  void enqueueFlushResult(Result<void> result) => _flushResults.add(result);

  @override
  Result<void> emit(MetricRecord record) {
    if (_results.isNotEmpty) {
      return _results.removeFirst();
    }
    records.add(record);
    return const Ok<void>(null);
  }

  @override
  Future<Result<void>> flush() async {
    flushCount += 1;
    return _flushResults.isNotEmpty
        ? _flushResults.removeFirst()
        : const Ok<void>(null);
  }
}

/// Thrown when a dependency-light `diene_interfaces` assertion fails.
///
/// Mirrors `diene_result`'s `TestHelperFailure`: a plain exception, so the
/// helpers work with `package:test`, `flutter_test`, or any other runner.
final class SeamAssertionFailure implements Exception {
  /// Creates an assertion failure with a consumer-facing diagnostic.
  const SeamAssertionFailure(this.message);

  /// Failure diagnostic.
  final String message;

  @override
  String toString() => 'SeamAssertionFailure: $message';
}

/// Requires [problem] to be the envelope this library mints for [port]/[code].
///
/// Consumers assert seam failures constantly; without this they would re-derive
/// the type URI, status, `recoverable` flag, and `data` shape in every test.
Problem expectPortProblem(
  Problem problem, {
  required PortName port,
  required PortErrorCode code,
  String? operation,
}) {
  final Object? actualPort = problem.data['port'];
  final Object? actualCode = problem.data['code'];
  if (actualPort != port.name || actualCode != code.wireId) {
    throw SeamAssertionFailure(
      'Expected a ${port.name}/${code.wireId} problem, got '
      '$actualPort/$actualCode.',
    );
  }
  if (problem.status != code.status) {
    throw SeamAssertionFailure(
      'Expected status ${code.status} for ${code.wireId}, got '
      '${problem.status}.',
    );
  }
  if (problem.recoverable != code.recoverable) {
    throw SeamAssertionFailure(
      'Expected recoverable=${code.recoverable} for ${code.wireId}, got '
      '${problem.recoverable}.',
    );
  }
  if (operation != null && problem.data['operation'] != operation) {
    throw SeamAssertionFailure(
      'Expected operation "$operation", got "${problem.data['operation']}".',
    );
  }
  return problem;
}
