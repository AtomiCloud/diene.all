/// Dependency-light in-memory implementations for diene interface consumers.
library;

import 'dart:collection';
import 'dart:convert';

import 'package:diene_interfaces/diene_interfaces.dart';
import 'package:diene_result/diene_result.dart';

/// A deterministic [System] with mutable in-memory process state.
final class InMemorySystem implements System {
  InMemorySystem({
    Map<String, String> environment = const <String, String>{},
    this.directory = '/',
    DateTime? now,
  }) : environmentVariables = Map<String, String>.of(environment),
       now = (now ?? DateTime.fromMillisecondsSinceEpoch(0, isUtc: true))
           .toUtc();

  final Map<String, String> environmentVariables;
  final List<Duration> requestedDelays = <Duration>[];
  final Queue<Result<String?>> _environmentResults = Queue<Result<String?>>();
  final Queue<Result<String>> _directoryResults = Queue<Result<String>>();
  final Queue<Result<DateTime>> _clockResults = Queue<Result<DateTime>>();
  final Queue<Result<void>> _delayResults = Queue<Result<void>>();

  String directory;
  DateTime now;

  void enqueueEnvironmentResult(Result<String?> result) {
    _environmentResults.add(result);
  }

  void enqueueDirectoryResult(Result<String> result) {
    _directoryResults.add(result);
  }

  void enqueueClockResult(Result<DateTime> result) {
    _clockResults.add(result);
  }

  void enqueueDelayResult(Result<void> result) {
    _delayResults.add(result);
  }

  @override
  Result<String?> environment(String name) => _environmentResults.isNotEmpty
      ? _environmentResults.removeFirst()
      : Success<String?>(environmentVariables[name]);

  @override
  Result<String> currentDirectory() => _directoryResults.isNotEmpty
      ? _directoryResults.removeFirst()
      : Success<String>(directory);

  @override
  Result<DateTime> nowUtc() => _clockResults.isNotEmpty
      ? _clockResults.removeFirst()
      : Success<DateTime>(now.toUtc());

  @override
  Future<Result<void>> delay(Duration duration) async {
    requestedDelays.add(duration);
    return _delayResults.isNotEmpty
        ? _delayResults.removeFirst()
        : const Success<void>(null);
  }
}

/// A stateful, byte-backed [Vfs].
///
/// Scripted results are FIFO and short-circuit the corresponding operation.
/// This supports deterministic fault injection without a mocking framework.
final class InMemoryVfs implements Vfs {
  InMemoryVfs({
    Map<String, List<int>> files = const <String, List<int>>{},
    Iterable<String> directories = const <String>['/'],
  }) : _files = <String, List<int>>{
         for (final MapEntry<String, List<int>> entry in files.entries)
           _normalize(entry.key): List<int>.of(entry.value),
       },
       _directories = <String>{
         '/',
         for (final String directory in directories) _normalize(directory),
       };

  final Map<String, List<int>> _files;
  final Set<String> _directories;
  final Queue<Result<bool>> _existsResults = Queue<Result<bool>>();
  final Queue<Result<List<int>>> _readBytesResults = Queue<Result<List<int>>>();
  final Queue<Result<String>> _readTextResults = Queue<Result<String>>();
  final Queue<Result<void>> _writeBytesResults = Queue<Result<void>>();
  final Queue<Result<void>> _writeTextResults = Queue<Result<void>>();
  final Queue<Result<List<VfsEntry>>> _listResults =
      Queue<Result<List<VfsEntry>>>();
  final Queue<Result<void>> _createDirectoryResults = Queue<Result<void>>();
  final Queue<Result<void>> _deleteResults = Queue<Result<void>>();

  Map<String, List<int>> get files =>
      UnmodifiableMapView<String, List<int>>(<String, List<int>>{
        for (final MapEntry<String, List<int>> entry in _files.entries)
          entry.key: List<int>.unmodifiable(entry.value),
      });

  Set<String> get directories => Set<String>.unmodifiable(_directories);

  void enqueueExistsResult(Result<bool> result) => _existsResults.add(result);

  void enqueueReadBytesResult(Result<List<int>> result) {
    _readBytesResults.add(result);
  }

  void enqueueReadTextResult(Result<String> result) {
    _readTextResults.add(result);
  }

  void enqueueWriteBytesResult(Result<void> result) {
    _writeBytesResults.add(result);
  }

  void enqueueWriteTextResult(Result<void> result) {
    _writeTextResults.add(result);
  }

  void enqueueListResult(Result<List<VfsEntry>> result) {
    _listResults.add(result);
  }

  void enqueueCreateDirectoryResult(Result<void> result) {
    _createDirectoryResults.add(result);
  }

  void enqueueDeleteResult(Result<void> result) {
    _deleteResults.add(result);
  }

  @override
  Future<Result<bool>> exists(String path) async {
    if (_existsResults.isNotEmpty) {
      return _existsResults.removeFirst();
    }
    final String normalized = _normalize(path);
    return Success<bool>(
      _files.containsKey(normalized) || _directories.contains(normalized),
    );
  }

  @override
  Future<Result<List<int>>> readBytes(String path) async {
    if (_readBytesResults.isNotEmpty) {
      return _readBytesResults.removeFirst();
    }
    final String normalized = _normalize(path);
    final List<int>? bytes = _files[normalized];
    return bytes == null
        ? _notFound<List<int>>(normalized)
        : Success<List<int>>(List<int>.unmodifiable(bytes));
  }

  @override
  Future<Result<String>> readText(String path) async {
    if (_readTextResults.isNotEmpty) {
      return _readTextResults.removeFirst();
    }
    final String normalized = _normalize(path);
    final List<int>? bytes = _files[normalized];
    return bytes == null
        ? _notFound<String>(normalized)
        : Success<String>(utf8.decode(bytes, allowMalformed: true));
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
    return _write(path, bytes, createParents: createParents);
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
    return _write(path, utf8.encode(content), createParents: createParents);
  }

  Result<void> _write(
    String path,
    List<int> bytes, {
    required bool createParents,
  }) {
    final String normalized = _normalize(path);
    final String parent = _parent(normalized);
    if (!_directories.contains(parent)) {
      if (!createParents) {
        return _notFound<void>(parent);
      }
      _createParents(parent);
    }
    _files[normalized] = List<int>.of(bytes);
    return const Success<void>(null);
  }

  @override
  Future<Result<List<VfsEntry>>> list(
    String path, {
    bool recursive = false,
  }) async {
    if (_listResults.isNotEmpty) {
      return _listResults.removeFirst();
    }
    final String normalized = _normalize(path);
    if (!_directories.contains(normalized)) {
      return _notFound<List<VfsEntry>>(normalized);
    }
    final String prefix = normalized == '/' ? '/' : '$normalized/';
    final List<VfsEntry> entries = <VfsEntry>[
      for (final String directory in _directories)
        if (directory != normalized &&
            directory.startsWith(prefix) &&
            (recursive || !_relative(directory, prefix).contains('/')))
          VfsEntry(path: directory, type: VfsEntryType.directory, size: 0),
      for (final MapEntry<String, List<int>> file in _files.entries)
        if (file.key.startsWith(prefix) &&
            (recursive || !_relative(file.key, prefix).contains('/')))
          VfsEntry(
            path: file.key,
            type: VfsEntryType.file,
            size: file.value.length,
          ),
    ]..sort((VfsEntry left, VfsEntry right) => left.path.compareTo(right.path));
    return Success<List<VfsEntry>>(List<VfsEntry>.unmodifiable(entries));
  }

  @override
  Future<Result<void>> createDirectory(
    String path, {
    bool recursive = false,
  }) async {
    if (_createDirectoryResults.isNotEmpty) {
      return _createDirectoryResults.removeFirst();
    }
    final String normalized = _normalize(path);
    final String parent = _parent(normalized);
    if (!_directories.contains(parent) && !recursive) {
      return _notFound<void>(parent);
    }
    if (recursive) {
      _createParents(normalized);
    } else {
      _directories.add(normalized);
    }
    return const Success<void>(null);
  }

  @override
  Future<Result<void>> delete(String path, {bool recursive = false}) async {
    if (_deleteResults.isNotEmpty) {
      return _deleteResults.removeFirst();
    }
    final String normalized = _normalize(path);
    if (_files.remove(normalized) != null) {
      return const Success<void>(null);
    }
    if (!_directories.contains(normalized)) {
      return _notFound<void>(normalized);
    }
    final String prefix = normalized == '/' ? '/' : '$normalized/';
    final bool hasChildren =
        _files.keys.any((String key) => key.startsWith(prefix)) ||
        _directories.any(
          (String directory) =>
              directory != normalized && directory.startsWith(prefix),
        );
    if (hasChildren && !recursive) {
      return _failure<void>(
        'directory-not-empty',
        'Directory not empty',
        normalized,
        status: 409,
      );
    }
    _files.removeWhere((String key, List<int> _) => key.startsWith(prefix));
    _directories.removeWhere(
      (String directory) =>
          directory == normalized || directory.startsWith(prefix),
    );
    _directories.add('/');
    return const Success<void>(null);
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

  static String _relative(String path, String prefix) =>
      path.substring(prefix.length);

  static String _parent(String path) {
    final int separator = path.lastIndexOf('/');
    return separator <= 0 ? '/' : path.substring(0, separator);
  }

  static String _normalize(String path) {
    final Iterable<String> segments = path
        .split('/')
        .where((String part) => part.isNotEmpty);
    final String normalized = '/${segments.join('/')}';
    return normalized == '' ? '/' : normalized;
  }
}

/// A FIFO-scripted [Terminal] that records every command.
final class InMemoryTerminal implements Terminal {
  final List<TerminalCommand> commands = <TerminalCommand>[];
  final Queue<Result<TerminalOutput>> _results =
      Queue<Result<TerminalOutput>>();

  void enqueue(Result<TerminalOutput> result) => _results.add(result);

  @override
  Future<Result<TerminalOutput>> run(TerminalCommand command) async {
    commands.add(command);
    return _results.isEmpty
        ? _failure<TerminalOutput>(
            'terminal-result-not-scripted',
            'Terminal result not scripted',
            command.executable,
          )
        : _results.removeFirst();
  }
}

/// An in-memory [LoggerSink] with FIFO fault injection.
final class InMemoryLoggerSink implements LoggerSink {
  final List<LogRecord> records = <LogRecord>[];
  final Queue<Result<void>> _results = Queue<Result<void>>();

  void enqueue(Result<void> result) => _results.add(result);

  @override
  Result<void> emit(LogRecord record) {
    if (_results.isNotEmpty) {
      return _results.removeFirst();
    }
    records.add(record);
    return const Success<void>(null);
  }
}

/// An in-memory [MetricsCollector] with FIFO fault injection.
final class InMemoryMetricsCollector implements MetricsCollector {
  final List<MetricRecord> records = <MetricRecord>[];
  final Queue<Result<void>> _results = Queue<Result<void>>();

  void enqueue(Result<void> result) => _results.add(result);

  @override
  Result<void> emit(MetricRecord record) {
    if (_results.isNotEmpty) {
      return _results.removeFirst();
    }
    records.add(record);
    return const Success<void>(null);
  }
}

Failure<T> _notFound<T>(String path) =>
    _failure<T>('path-not-found', 'Path not found', path, status: 404);

Failure<T> _failure<T>(
  String id,
  String title,
  String detail, {
  int status = 500,
}) => Failure<T>(
  Problem(
    type: 'https://diene.atomicloud.com/problems/interfaces/1/$id',
    title: title,
    status: status,
    detail: detail,
    data: <String, Object?>{'id': id},
  ),
);
