import 'dart:convert';

import 'package:diene_interfaces/diene_interfaces.dart';
import 'package:diene_interfaces/test_helper.dart';
import 'package:diene_result/diene_result.dart';
import 'package:diene_result/test_helper.dart';
import 'package:test/test.dart';

InMemoryVfs _seeded() => InMemoryVfs(
  files: <String, List<int>>{
    '/a/one.txt': utf8.encode('one'),
    '/a/b/two.txt': utf8.encode('two'),
  },
  modifiedAt: DateTime.utc(2026, 7, 25),
);

void main() {
  group('InMemoryVfs seeding and normalisation', () {
    test('normalises seeded paths and materialises their parents', () async {
      // Arrange.
      final InMemoryVfs vfs = InMemoryVfs(
        files: <String, List<int>>{'a//b/c.txt': utf8.encode('x')},
      );

      // Act.
      final bool exists = expectOk(await vfs.exists('/a/b/c.txt'));

      // Assert.
      expect(exists, isTrue);
      expect(vfs.directories, containsAll(<String>['/', '/a', '/a/b']));
      expect(vfs.files.keys, <String>['/a/b/c.txt']);
    });

    test('collapses a blank path to the root', () {
      // Arrange & Act & Assert.
      expect(InMemoryVfs.normalizePath(''), '/');
      expect(InMemoryVfs.normalizePath('//'), '/');
      expect(InMemoryVfs.normalizePath('a/b'), '/a/b');
    });

    test('exposes deeply unmodifiable snapshots', () {
      // Arrange.
      final InMemoryVfs vfs = _seeded();

      // Act.
      final Map<String, List<int>> files = vfs.files;

      // Assert.
      expect(() => files.clear(), throwsUnsupportedError);
      expect(() => files['/a/one.txt']!.add(0), throwsUnsupportedError);
      expect(() => vfs.directories.add('/x'), throwsUnsupportedError);
    });

    test('seeds extra directories', () async {
      // Arrange.
      final InMemoryVfs vfs = InMemoryVfs(directories: <String>['/only']);

      // Act & Assert.
      expect(expectOk(await vfs.exists('/only')), isTrue);
      expect(expectOk(await vfs.exists('/absent')), isFalse);
    });
  });

  group('InMemoryVfs reads', () {
    test(
      'reads bytes and text, and rejects a missing path as a value',
      () async {
        // Arrange.
        final InMemoryVfs vfs = _seeded();

        // Act.
        final List<int> bytes = expectOk(await vfs.readBytes('/a/one.txt'));
        final String text = expectOk(await vfs.readText('/a/b/two.txt'));

        // Assert.
        expect(utf8.decode(bytes), 'one');
        expect(text, 'two');
        expect(() => bytes.add(0), throwsUnsupportedError);
        expectPortProblem(
          expectErr(await vfs.readBytes('/absent')),
          port: PortName.vfs,
          code: PortErrorCode.notFound,
          operation: 'readBytes',
        );
        expectPortProblem(
          expectErr(await vfs.readText('/absent')),
          port: PortName.vfs,
          code: PortErrorCode.notFound,
          operation: 'readText',
        );
      },
    );

    test('decodes malformed bytes instead of throwing', () async {
      // Arrange.
      final InMemoryVfs vfs = InMemoryVfs(
        files: <String, List<int>>{
          '/bad.bin': <int>[0xff, 0xfe],
        },
      );

      // Act.
      final String text = expectOk(await vfs.readText('/bad.bin'));

      // Assert.
      expect(text, isNotEmpty);
    });

    test('stats files, directories, and absent paths', () async {
      // Arrange.
      final InMemoryVfs vfs = _seeded();

      // Act.
      final VfsStat file = expectOk(await vfs.stat('/a/one.txt'));
      final VfsStat directory = expectOk(await vfs.stat('/a'));

      // Assert.
      expect(file.type, VfsEntryType.file);
      expect(file.size, 3);
      expect(file.modifiedAt, DateTime.utc(2026, 7, 25));
      expect(directory.type, VfsEntryType.directory);
      expect(directory.size, 0);
      expectPortProblem(
        expectErr(await vfs.stat('/absent')),
        port: PortName.vfs,
        code: PortErrorCode.notFound,
        operation: 'stat',
      );
    });
  });

  group('InMemoryVfs writes', () {
    test('writes bytes and text into an existing directory', () async {
      // Arrange.
      final InMemoryVfs vfs = _seeded();

      // Act.
      expectOk(await vfs.writeBytes('/a/three.bin', <int>[1, 2]));
      expectOk(await vfs.writeText('/a/four.txt', 'four'));

      // Assert.
      expect(expectOk(await vfs.readBytes('/a/three.bin')), <int>[1, 2]);
      expect(expectOk(await vfs.readText('/a/four.txt')), 'four');
    });

    test('refuses a missing parent unless createParents is set', () async {
      // Arrange.
      final InMemoryVfs vfs = _seeded();

      // Act & Assert.
      expectPortProblem(
        expectErr(await vfs.writeBytes('/new/deep/x.bin', <int>[1])),
        port: PortName.vfs,
        code: PortErrorCode.notFound,
        operation: 'writeBytes',
      );
      expectPortProblem(
        expectErr(await vfs.writeText('/new/deep/x.txt', 'x')),
        port: PortName.vfs,
        code: PortErrorCode.notFound,
        operation: 'writeText',
      );
      expectOk(
        await vfs.writeText('/new/deep/x.txt', 'x', createParents: true),
      );
      expect(vfs.directories, containsAll(<String>['/new', '/new/deep']));
    });

    test('copies written bytes so the caller cannot mutate storage', () async {
      // Arrange.
      final InMemoryVfs vfs = InMemoryVfs();
      final List<int> bytes = <int>[1];

      // Act.
      expectOk(await vfs.writeBytes('/x.bin', bytes));
      bytes.add(2);

      // Assert.
      expect(expectOk(await vfs.readBytes('/x.bin')), <int>[1]);
    });
  });

  group('InMemoryVfs listing', () {
    test('lists a directory shallowly and recursively, sorted', () async {
      // Arrange.
      final InMemoryVfs vfs = _seeded();

      // Act.
      final List<VfsEntry> shallow = expectOk(await vfs.list('/a'));
      final List<VfsEntry> deep = expectOk(
        await vfs.list('/a', recursive: true),
      );

      // Assert.
      expect(shallow.map((VfsEntry entry) => entry.path), <String>[
        '/a/b',
        '/a/one.txt',
      ]);
      expect(deep.map((VfsEntry entry) => entry.path), <String>[
        '/a/b',
        '/a/b/two.txt',
        '/a/one.txt',
      ]);
      expect(shallow.first.type, VfsEntryType.directory);
      expect(() => shallow.add(shallow.first), throwsUnsupportedError);
    });

    test('lists the root', () async {
      // Arrange.
      final InMemoryVfs vfs = InMemoryVfs(
        files: <String, List<int>>{'/top.txt': utf8.encode('t')},
      );

      // Act.
      final List<VfsEntry> entries = expectOk(await vfs.list('/'));

      // Assert.
      expect(entries.map((VfsEntry entry) => entry.path), <String>['/top.txt']);
    });

    test('rejects listing an unknown directory as a value', () async {
      // Arrange & Act & Assert.
      expectPortProblem(
        expectErr(await InMemoryVfs().list('/absent')),
        port: PortName.vfs,
        code: PortErrorCode.notFound,
        operation: 'list',
      );
    });
  });

  group('InMemoryVfs directory creation and deletion', () {
    test('creates a directory beside an existing parent', () async {
      // Arrange.
      final InMemoryVfs vfs = _seeded();

      // Act.
      expectOk(await vfs.createDirectory('/a/c'));

      // Assert.
      expect(vfs.directories, contains('/a/c'));
    });

    test('refuses a missing parent unless recursive', () async {
      // Arrange.
      final InMemoryVfs vfs = InMemoryVfs();

      // Act & Assert.
      expectPortProblem(
        expectErr(await vfs.createDirectory('/x/y')),
        port: PortName.vfs,
        code: PortErrorCode.notFound,
        operation: 'createDirectory',
      );
      expectOk(await vfs.createDirectory('/x/y', recursive: true));
      expect(vfs.directories, containsAll(<String>['/x', '/x/y']));
    });

    test('deletes a file, and reports an unknown path as a value', () async {
      // Arrange.
      final InMemoryVfs vfs = _seeded();

      // Act.
      expectOk(await vfs.delete('/a/one.txt'));

      // Assert.
      expect(expectOk(await vfs.exists('/a/one.txt')), isFalse);
      expectPortProblem(
        expectErr(await vfs.delete('/a/one.txt')),
        port: PortName.vfs,
        code: PortErrorCode.notFound,
        operation: 'delete',
      );
    });

    test('refuses a non-empty directory unless recursive', () async {
      // Arrange.
      final InMemoryVfs vfs = _seeded();

      // Act.
      final Object problem = expectErr(await vfs.delete('/a'));

      // Assert.
      expectPortProblem(
        expectErr(await vfs.delete('/a')),
        port: PortName.vfs,
        code: PortErrorCode.directoryNotEmpty,
        operation: 'delete',
      );
      expect(problem, isNotNull);
      expectOk(await vfs.delete('/a', recursive: true));
      expect(expectOk(await vfs.exists('/a')), isFalse);
      expect(expectOk(await vfs.exists('/a/b/two.txt')), isFalse);
      expect(vfs.directories, <String>{'/'});
    });

    test('deletes an empty directory without the recursive flag', () async {
      // Arrange.
      final InMemoryVfs vfs = InMemoryVfs(directories: <String>['/empty']);

      // Act.
      expectOk(await vfs.delete('/empty'));

      // Assert.
      expect(vfs.directories, <String>{'/'});
    });
  });

  group('InMemoryVfs scripted results', () {
    test('every fallible member honours one scripted answer', () async {
      // Arrange.
      final InMemoryVfs vfs = _seeded()
        ..enqueueExistsResult(const Ok<bool>(true))
        ..enqueueStatResult(
          const Ok<VfsStat>(VfsStat(type: VfsEntryType.link, size: 0)),
        )
        ..enqueueReadBytesResult(const Ok<List<int>>(<int>[9]))
        ..enqueueReadTextResult(const Ok<String>('scripted'))
        ..enqueueWriteBytesResult(const Ok<void>(null))
        ..enqueueWriteTextResult(const Ok<void>(null))
        ..enqueueListResult(const Ok<List<VfsEntry>>(<VfsEntry>[]))
        ..enqueueCreateDirectoryResult(const Ok<void>(null))
        ..enqueueDeleteResult(const Ok<void>(null));

      // Act & Assert.
      expect(expectOk(await vfs.exists('/whatever')), isTrue);
      expect(expectOk(await vfs.stat('/whatever')).type, VfsEntryType.link);
      expect(expectOk(await vfs.readBytes('/whatever')), <int>[9]);
      expect(expectOk(await vfs.readText('/whatever')), 'scripted');
      expectOk(await vfs.writeBytes('/nowhere/x', <int>[1]));
      expectOk(await vfs.writeText('/nowhere/x', 'x'));
      expect(expectOk(await vfs.list('/nowhere')), isEmpty);
      expectOk(await vfs.createDirectory('/nowhere/deep'));
      expectOk(await vfs.delete('/nowhere'));
      // The scripts are consumed, so real behaviour resumes.
      expect(expectOk(await vfs.exists('/absent')), isFalse);
    });
  });
}
