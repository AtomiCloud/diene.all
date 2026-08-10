/// The portable filesystem boundary.
library;

import 'package:diene_result/diene_result.dart';

import 'port_problem.dart';

/// The kind of entry a filesystem path resolves to.
enum VfsEntryType {
  /// A regular file.
  file,

  /// A directory.
  directory,

  /// A symbolic link.
  link,
}

/// Metadata for one virtual filesystem entry.
final class VfsEntry {
  /// Creates an entry description.
  const VfsEntry({
    required this.path,
    required this.type,
    required this.size,
    this.modifiedAt,
  });

  /// Absolute path of the entry.
  final String path;

  /// What the path resolves to.
  final VfsEntryType type;

  /// Size in bytes; `0` for directories and links.
  final int size;

  /// Last-modified instant when the host reports one.
  final DateTime? modifiedAt;

  @override
  String toString() => 'VfsEntry($path, ${type.name}, $size)';
}

/// Metadata for a single path, without listing its parent.
final class VfsStat {
  /// Creates a stat result.
  const VfsStat({required this.type, required this.size, this.modifiedAt});

  /// What the path resolves to.
  final VfsEntryType type;

  /// Size in bytes; `0` for directories and links.
  final int size;

  /// Last-modified instant when the host reports one.
  final DateTime? modifiedAt;

  @override
  String toString() => 'VfsStat(${type.name}, $size)';
}

/// A portable virtual filesystem boundary.
///
/// Paths are opaque strings: path normalisation and sandbox policy belong to
/// implementations, not to this contract. Every host operation returns a
/// `Result` and must not throw to communicate an expected failure.
abstract interface class Vfs {
  /// Reports whether [path] resolves to anything.
  Future<Result<bool>> exists(String path);

  /// Describes [path] without listing its parent.
  Future<Result<VfsStat>> stat(String path);

  /// Reads [path] as bytes.
  Future<Result<List<int>>> readBytes(String path);

  /// Reads [path] as UTF-8 text.
  Future<Result<String>> readText(String path);

  /// Writes [bytes] to [path], optionally creating missing parents.
  Future<Result<void>> writeBytes(
    String path,
    List<int> bytes, {
    bool createParents = false,
  });

  /// Writes [content] to [path] as UTF-8, optionally creating missing parents.
  Future<Result<void>> writeText(
    String path,
    String content, {
    bool createParents = false,
  });

  /// Lists the entries directly (or, when [recursive], transitively) under
  /// [path].
  Future<Result<List<VfsEntry>>> list(String path, {bool recursive = false});

  /// Creates the directory at [path].
  Future<Result<void>> createDirectory(String path, {bool recursive = false});

  /// Deletes the file or directory at [path].
  Future<Result<void>> delete(String path, {bool recursive = false});
}

/// Validates a path an implementation is about to hand to a real host.
///
/// Offered TO implementations; the `Vfs` contract itself does not mandate it,
/// because a virtual or archive-backed filesystem may accept path shapes a
/// POSIX host would not. Rejects blank paths, NUL bytes, and relative paths.
Result<String> checkVfsPath(String path, {String operation = 'path'}) {
  if (path.trim().isEmpty) {
    return invalidInput<String>(
      port: PortName.vfs,
      operation: operation,
      field: 'path',
      message: 'Path must be non-blank',
    );
  }
  if (path.codeUnits.contains(0)) {
    return invalidInput<String>(
      port: PortName.vfs,
      operation: operation,
      field: 'path',
      message: 'Path must not contain a NUL byte',
    );
  }
  if (!path.startsWith('/')) {
    return invalidInput<String>(
      port: PortName.vfs,
      operation: operation,
      field: 'path',
      message: 'Path must be absolute',
    );
  }
  return Ok<String>(path);
}
