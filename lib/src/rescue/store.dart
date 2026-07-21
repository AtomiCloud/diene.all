import 'dart:io';

/// Durable key/value seam the rescue router persists to. Last-known-good and
/// the current pin are kept FOREVER (never TTL-expired). Flutter consumers back
/// this with real device disk (e.g. path_provider + a file); the engine stays
/// pure Dart by depending only on this seam.
abstract interface class RescueStore {
  Future<String?> read(String key);
  Future<void> write(String key, String value);
  Future<void> delete(String key);
}

/// In-memory store — the default when no disk is wired, and the base the test
/// fake extends.
class InMemoryRescueStore implements RescueStore {
  InMemoryRescueStore([Map<String, String>? seed])
      : _data = <String, String>{...?seed};

  final Map<String, String> _data;

  @override
  Future<String?> read(String key) async => _data[key];

  @override
  Future<void> write(String key, String value) async => _data[key] = value;

  @override
  Future<void> delete(String key) async => _data.remove(key);
}

/// dart:io file-backed store. One JSON-ish flat file per key under [directory].
/// Pure Dart — no Flutter/path_provider dependency; the consumer supplies the
/// directory (Flutter passes an app-documents path).
class FileRescueStore implements RescueStore {
  FileRescueStore(this.directory);

  final Directory directory;

  File _file(String key) {
    final String safe = key.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');
    return File('${directory.path}/rescue_$safe.txt');
  }

  @override
  Future<String?> read(String key) async {
    final File file = _file(key);
    return file.existsSync() ? file.readAsString() : null;
  }

  @override
  Future<void> write(String key, String value) async {
    await directory.create(recursive: true);
    await _file(key).writeAsString(value);
  }

  @override
  Future<void> delete(String key) async {
    final File file = _file(key);
    if (file.existsSync()) {
      await file.delete();
    }
  }
}
