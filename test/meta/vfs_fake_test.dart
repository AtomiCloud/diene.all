import 'dart:convert';

import 'package:diene_interfaces/diene_interfaces.dart';
import 'package:diene_interfaces/test_helper.dart';
import 'package:diene_result/diene_result.dart';
import 'package:test/test.dart';

import '../support/result_expectations.dart';

void main() {
  group('InMemoryVfs', () {
    test('reads seeded bytes and returns immutable snapshots', () async {
      // Arrange.
      final List<int> seed = utf8.encode('hello');
      final InMemoryVfs vfs = InMemoryVfs(
        files: <String, List<int>>{'//docs//hello.txt': seed},
        directories: const <String>['/docs'],
      );
      seed[0] = 0;

      // Act.
      final Result<bool> exists = await vfs.exists('/docs/hello.txt');
      final Result<List<int>> bytes = await vfs.readBytes('/docs/hello.txt');
      final Result<String> text = await vfs.readText('/docs/hello.txt');

      // Assert.
      expect(expectSuccess(exists), isTrue);
      expect(utf8.decode(expectSuccess(bytes)), 'hello');
      expect(expectSuccess(text), 'hello');
      expect(() => expectSuccess(bytes).add(1), throwsUnsupportedError);
      expect(vfs.files['/docs/hello.txt'], utf8.encode('hello'));
      expect(() => vfs.directories.add('/other'), throwsUnsupportedError);
    });

    test('writes text and bytes with explicit parent policy', () async {
      // Arrange.
      final InMemoryVfs vfs = InMemoryVfs(directories: const <String>['/data']);

      // Act.
      final Result<void> text = await vfs.writeText('/data/note.txt', 'note');
      final Result<void> bytes = await vfs.writeBytes(
        '/deep/path/value.bin',
        <int>[1, 2],
        createParents: true,
      );
      final Result<void> missingParent = await vfs.writeText('/absent/a', 'x');

      // Assert.
      expectSuccess(text);
      expectSuccess(bytes);
      expect(utf8.decode(vfs.files['/data/note.txt']!), 'note');
      expect(vfs.files['/deep/path/value.bin'], <int>[1, 2]);
      expect(vfs.directories, containsAll(<String>['/deep', '/deep/path']));
      expect(expectFailure(missingParent).status, 404);
    });

    test(
      'creates directories recursively and lists direct or nested entries',
      () async {
        // Arrange.
        final InMemoryVfs vfs = InMemoryVfs();

        // Act.
        final Result<void> recursive = await vfs.createDirectory(
          '/a/b',
          recursive: true,
        );
        final Result<void> direct = await vfs.createDirectory('/a/c');
        await vfs.writeText('/a/root.txt', 'r');
        await vfs.writeText('/a/b/nested.txt', 'n');
        final Result<List<VfsEntry>> shallow = await vfs.list('/a');
        final Result<List<VfsEntry>> deep = await vfs.list(
          '/a',
          recursive: true,
        );
        final Result<void> invalid = await vfs.createDirectory(
          '/missing/child',
        );

        // Assert.
        expectSuccess(recursive);
        expectSuccess(direct);
        expect(
          expectSuccess(shallow).map((VfsEntry entry) => entry.path),
          <String>['/a/b', '/a/c', '/a/root.txt'],
        );
        expect(expectSuccess(deep), hasLength(4));
        expect(expectFailure(invalid).status, 404);
      },
    );

    test('deletes files and enforces recursive directory deletion', () async {
      // Arrange.
      final InMemoryVfs vfs = InMemoryVfs(
        files: <String, List<int>>{
          '/tree/a.txt': <int>[1],
          '/tree/nested/b.txt': <int>[2],
        },
        directories: const <String>['/tree', '/tree/nested'],
      );

      // Act.
      final Result<void> file = await vfs.delete('/tree/a.txt');
      final Result<void> nonRecursive = await vfs.delete('/tree');
      final Result<void> recursive = await vfs.delete('/tree', recursive: true);
      final Result<void> missing = await vfs.delete('/tree');

      // Assert.
      expectSuccess(file);
      expect(expectFailure(nonRecursive).status, 409);
      expectSuccess(recursive);
      expect(expectFailure(missing).status, 404);
      expect(vfs.directories, <String>{'/'});
      expect(vfs.files, isEmpty);
    });

    test('returns Result failures for missing reads and lists', () async {
      // Arrange.
      final InMemoryVfs vfs = InMemoryVfs();

      // Act.
      final Result<List<int>> bytes = await vfs.readBytes('/missing');
      final Result<String> text = await vfs.readText('/missing');
      final Result<List<VfsEntry>> list = await vfs.list('/missing');
      final Result<bool> exists = await vfs.exists('/missing');

      // Assert.
      expect(expectFailure(bytes).data['id'], 'path-not-found');
      expect(expectFailure(text).detail, '/missing');
      expect(expectFailure(list).type, contains('path-not-found'));
      expect(expectSuccess(exists), isFalse);
    });

    test('scripted results short-circuit every operation', () async {
      // Arrange.
      final InMemoryVfs vfs = InMemoryVfs();
      final Err<bool> existsFailure = failure<bool>('exists');
      final Err<List<int>> readBytesFailure = failure<List<int>>('read-bytes');
      final Err<String> readTextFailure = failure<String>('read-text');
      final Err<void> writeBytesFailure = failure<void>('write-bytes');
      final Err<void> writeTextFailure = failure<void>('write-text');
      final Err<List<VfsEntry>> listFailure = failure<List<VfsEntry>>('list');
      final Err<void> createFailure = failure<void>('create');
      final Err<void> deleteFailure = failure<void>('delete');
      vfs.enqueueExistsResult(existsFailure);
      vfs.enqueueReadBytesResult(readBytesFailure);
      vfs.enqueueReadTextResult(readTextFailure);
      vfs.enqueueWriteBytesResult(writeBytesFailure);
      vfs.enqueueWriteTextResult(writeTextFailure);
      vfs.enqueueListResult(listFailure);
      vfs.enqueueCreateDirectoryResult(createFailure);
      vfs.enqueueDeleteResult(deleteFailure);

      // Act and assert.
      expect(await vfs.exists('/x'), same(existsFailure));
      expect(await vfs.readBytes('/x'), same(readBytesFailure));
      expect(await vfs.readText('/x'), same(readTextFailure));
      expect(await vfs.writeBytes('/x', <int>[]), same(writeBytesFailure));
      expect(await vfs.writeText('/x', ''), same(writeTextFailure));
      expect(await vfs.list('/x'), same(listFailure));
      expect(await vfs.createDirectory('/x'), same(createFailure));
      expect(await vfs.delete('/x'), same(deleteFailure));
    });
  });
}
