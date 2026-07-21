import 'package:diene_result/diene_result.dart';

/// The kind of entry returned by [Vfs.list].
enum VfsEntryType { file, directory, link }

/// Metadata for one virtual filesystem entry.
final class VfsEntry {
  const VfsEntry({
    required this.path,
    required this.type,
    required this.size,
    this.modifiedAt,
  });

  final String path;
  final VfsEntryType type;
  final int size;
  final DateTime? modifiedAt;
}

/// A portable virtual filesystem boundary.
///
/// Paths are opaque strings. Path normalization and sandbox policy belong to
/// implementations, not this contract. Every host operation returns a
/// [Result] and must not throw to communicate an expected failure.
abstract interface class Vfs {
  Future<Result<bool>> exists(String path);

  Future<Result<List<int>>> readBytes(String path);

  Future<Result<String>> readText(String path);

  Future<Result<void>> writeBytes(
    String path,
    List<int> bytes, {
    bool createParents = false,
  });

  Future<Result<void>> writeText(
    String path,
    String content, {
    bool createParents = false,
  });

  Future<Result<List<VfsEntry>>> list(String path, {bool recursive = false});

  Future<Result<void>> createDirectory(String path, {bool recursive = false});

  Future<Result<void>> delete(String path, {bool recursive = false});
}
