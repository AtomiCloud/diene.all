import 'package:diene_core_utils/diene_core_utils.dart';
import 'package:diene_interfaces/diene_interfaces.dart';
import 'package:diene_interfaces/test_helper.dart';
import 'package:diene_problems/diene_problems.dart';
import 'package:diene_result/diene_result.dart';
import 'package:test/test.dart';

/// Real consumption of the PUBLISHED `diene_interfaces` 1.0.0 seam (R-E12).
///
/// Two obligations are discharged here:
///
/// 1. **A seam injected through its interface type.** Every member under test
///    takes `Vfs` — the published INTERFACE — as a parameter. The suite proves
///    that by driving the same members through a second, independent `Vfs`
///    implementation ([_RecordingVfs]) defined in this file: if the production
///    code had reached for a concrete type or `dart:io` instead of the seam, the
///    substitution below could not compile.
/// 2. **The shipped fakes.** The happy paths run against
///    `package:diene_interfaces/test_helper.dart`'s `InMemoryVfs`, including its
///    FIFO scripted-failure mechanism, so failure branches are exercised with no
///    host filesystem and no mocking framework.
void main() {
  group('readVfsText / writeVfsText through the published Vfs seam', () {
    test('a write is readable back through the same seam', () async {
      final InMemoryVfs vfs = InMemoryVfs();

      final Result<void> written = await writeVfsText(
        vfs,
        '/etc/diene/base.yaml',
        'app:\n  name: base\n',
      );
      expect(written.isOk, isTrue, reason: _describe(written));

      final Result<String> read = await readVfsText(
        vfs,
        '/etc/diene/base.yaml',
      );
      expect(read.isOk, isTrue, reason: _describe(read));
      expect(read.unwrap(), 'app:\n  name: base\n');
    });

    test('writeVfsText creates missing parents', () async {
      final InMemoryVfs vfs = InMemoryVfs();
      final Result<void> written = await writeVfsText(
        vfs,
        '/deeply/nested/parents/config.yaml',
        'x: 1',
      );
      expect(written.isOk, isTrue, reason: _describe(written));
      expect(
        (await vfs.exists('/deeply/nested/parents/config.yaml')).unwrap(),
        isTrue,
      );
    });

    test("a seam failure is propagated UNCHANGED, not re-wrapped", () async {
      final InMemoryVfs vfs = InMemoryVfs();
      final Result<String> read = await readVfsText(vfs, '/absent.yaml');

      expect(read.isErr, isTrue);
      final Problem problem = read.unwrapErr();
      // The envelope must still be the SEAM's: port=vfs, not util=vfs. A
      // re-wrapped envelope would bury the real cause behind a second one.
      expect(problem.data['port'], 'vfs');
      expect(problem.data.containsKey('util'), isFalse);
      expect(problem.status, 404);
    });
  });

  group('readOptionalVfsText', () {
    test('absence is a successful null, not a failure', () async {
      final InMemoryVfs vfs = InMemoryVfs();
      final Result<String?> read = await readOptionalVfsText(
        vfs,
        '/absent.yaml',
      );
      expect(read.isOk, isTrue, reason: _describe(read));
      expect(read.unwrap(), isNull);
    });

    test('a present layer returns its text', () async {
      final InMemoryVfs vfs = InMemoryVfs();
      (await writeVfsText(
        vfs,
        '/overlay.yaml',
        'app:\n  name: overlay\n',
      )).unwrap();
      final Result<String?> read = await readOptionalVfsText(
        vfs,
        '/overlay.yaml',
      );
      expect(read.unwrap(), 'app:\n  name: overlay\n');
    });

    test('a non-absence failure from exists() still propagates', () async {
      final InMemoryVfs vfs = InMemoryVfs()
        ..enqueueExistsResult(
          portFailure<bool>(
            port: PortName.vfs,
            code: PortErrorCode.permissionDenied,
            operation: "exists",
            message: "host refused",
          ),
        );
      final Result<String?> read = await readOptionalVfsText(
        vfs,
        '/guarded.yaml',
      );
      expect(read.isErr, isTrue, reason: 'a permission error is not absence');
      expect(read.unwrapErr().status, 403);
    });

    test('a failure AFTER a positive exists() still propagates', () async {
      final _RecordingVfs vfs = _RecordingVfs(
        existsResult: const Ok<bool>(true),
        readResult: Err<String>(
          _problem(PortErrorCode.io, 'read', 'device fell over'),
        ),
      );
      final Result<String?> read = await readOptionalVfsText(
        vfs,
        '/flaky.yaml',
      );
      expect(read.isErr, isTrue);
      expect(read.unwrapErr().status, 500);
      expect(vfs.calls, <String>['exists:/flaky.yaml', 'readText:/flaky.yaml']);
    });
  });

  group('loadConfigLayers — the C0 §3 ladder over a real seam', () {
    test('layers merge in order with the later layer winning', () async {
      final InMemoryVfs vfs = InMemoryVfs();
      (await writeVfsText(vfs, '/base.kv', 'name=base\nretries=1\n')).unwrap();
      (await writeVfsText(vfs, '/landscape.kv', 'retries=2\n')).unwrap();

      final Result<JsonObject> loaded =
          await loadConfigLayers(vfs, <ConfigLayer>[
            const ConfigLayer(path: '/base.kv', parse: _parseKeyValue),
            const ConfigLayer(path: '/landscape.kv', parse: _parseKeyValue),
          ]);

      expect(loaded.isOk, isTrue, reason: _describe(loaded));
      expect(loaded.unwrap(), <String, Object?>{
        'name': 'base',
        'retries': '2',
      });
    });

    test('an absent OPTIONAL layer contributes nothing', () async {
      final InMemoryVfs vfs = InMemoryVfs();
      (await writeVfsText(vfs, '/base.kv', 'name=base\n')).unwrap();

      final Result<JsonObject> loaded =
          await loadConfigLayers(vfs, <ConfigLayer>[
            const ConfigLayer(path: '/base.kv', parse: _parseKeyValue),
            const ConfigLayer(
              path: '/never-written.kv',
              parse: _parseKeyValue,
              optional: true,
            ),
          ]);

      expect(loaded.unwrap(), <String, Object?>{'name': 'base'});
    });

    test('an absent REQUIRED layer fails with the seam envelope', () async {
      final InMemoryVfs vfs = InMemoryVfs();
      final Result<JsonObject> loaded = await loadConfigLayers(
        vfs,
        <ConfigLayer>[
          const ConfigLayer(path: '/required.kv', parse: _parseKeyValue),
        ],
      );

      expect(loaded.isErr, isTrue);
      expect(loaded.unwrapErr().data['port'], 'vfs');
      expect(loaded.unwrapErr().status, 404);
    });

    test('an optional layer whose exists() fails aborts the load', () async {
      final InMemoryVfs vfs = InMemoryVfs()
        ..enqueueExistsResult(
          portFailure<bool>(
            port: PortName.vfs,
            code: PortErrorCode.unavailable,
            operation: "exists",
            message: "host unavailable",
          ),
        );
      final Result<JsonObject> loaded = await loadConfigLayers(
        vfs,
        <ConfigLayer>[
          const ConfigLayer(
            path: '/overlay.kv',
            parse: _parseKeyValue,
            optional: true,
          ),
        ],
      );
      expect(loaded.isErr, isTrue);
      expect(loaded.unwrapErr().status, 503);
      // The seam declared this one retryable; core-utils must not flatten that.
      expect(loaded.unwrapErr().recoverable, isTrue);
    });

    test('a parse failure aborts the load and is returned unchanged', () async {
      final InMemoryVfs vfs = InMemoryVfs();
      (await writeVfsText(vfs, '/broken.kv', 'no-equals-sign\n')).unwrap();

      final Result<JsonObject> loaded = await loadConfigLayers(
        vfs,
        <ConfigLayer>[
          const ConfigLayer(path: '/broken.kv', parse: _parseKeyValue),
        ],
      );

      expect(loaded.isErr, isTrue);
      expect(loaded.unwrapErr().title, 'malformed key=value line');
    });

    test(
      'no layer present at all is a core-utils failure, not a seam one',
      () async {
        final InMemoryVfs vfs = InMemoryVfs();
        final Result<JsonObject> loaded =
            await loadConfigLayers(vfs, <ConfigLayer>[
              const ConfigLayer(
                path: '/a.kv',
                parse: _parseKeyValue,
                optional: true,
              ),
              const ConfigLayer(
                path: '/b.kv',
                parse: _parseKeyValue,
                optional: true,
              ),
            ]);

        expect(loaded.isErr, isTrue);
        final Problem problem = loaded.unwrapErr();
        expect(problem.data['util'], 'vfs');
        expect(problem.data['code'], 'invalid_input');
        expect(problem.data['paths'], <String>['/a.kv', '/b.kv']);
        expect(problem.status, 400);
      },
    );

    test('an empty layer list reports the same no-layer failure', () async {
      final InMemoryVfs vfs = InMemoryVfs();
      final Result<JsonObject> loaded = await loadConfigLayers(
        vfs,
        <ConfigLayer>[],
      );
      expect(loaded.isErr, isTrue);
      expect(loaded.unwrapErr().data['paths'], <String>[]);
    });
  });

  group('interface-type injection (not a concrete implementation)', () {
    test(
      'an independent Vfs implementation drives the identical members',
      () async {
        // This is the substitution proof: _RecordingVfs shares no code with
        // InMemoryVfs, so the members below can only be reaching the published
        // `Vfs` INTERFACE.
        final _RecordingVfs vfs = _RecordingVfs(
          existsResult: const Ok<bool>(true),
          readResult: const Ok<String>('name=recorded\n'),
        );

        expect((await readVfsText(vfs, '/x.kv')).unwrap(), 'name=recorded\n');
        expect(
          (await readOptionalVfsText(vfs, '/x.kv')).unwrap(),
          'name=recorded\n',
        );
        expect(
          (await writeVfsText(vfs, '/x.kv', 'name=written\n')).isOk,
          isTrue,
        );

        final Result<JsonObject> loaded = await loadConfigLayers(
          vfs,
          <ConfigLayer>[
            const ConfigLayer(path: '/x.kv', parse: _parseKeyValue),
          ],
        );
        expect(loaded.unwrap(), <String, Object?>{'name': 'recorded'});

        expect(vfs.calls, <String>[
          'readText:/x.kv',
          'exists:/x.kv',
          'readText:/x.kv',
          'writeText:/x.kv:createParents=true',
          'readText:/x.kv',
        ]);
      },
    );
  });
}

/// A second, independent `Vfs` used to prove the members bind the INTERFACE.
///
/// Only the operations `diene_core_utils` actually calls are implemented; every
/// other member of the contract reports `unsupported` rather than throwing, which
/// is itself the contract's rule for a boundary that does not implement an
/// operation.
final class _RecordingVfs implements Vfs {
  _RecordingVfs({required this.existsResult, required this.readResult});

  final Result<bool> existsResult;
  final Result<String> readResult;
  final List<String> calls = <String>[];

  @override
  Future<Result<bool>> exists(String path) async {
    calls.add('exists:$path');
    return existsResult;
  }

  @override
  Future<Result<String>> readText(String path) async {
    calls.add('readText:$path');
    return readResult;
  }

  @override
  Future<Result<void>> writeText(
    String path,
    String content, {
    bool createParents = false,
  }) async {
    calls.add('writeText:$path:createParents=$createParents');
    return const Ok<void>(null);
  }

  @override
  Future<Result<VfsStat>> stat(String path) async =>
      _unsupported<VfsStat>('stat');

  @override
  Future<Result<List<int>>> readBytes(String path) async =>
      _unsupported<List<int>>('readBytes');

  @override
  Future<Result<void>> writeBytes(
    String path,
    List<int> bytes, {
    bool createParents = false,
  }) async => _unsupported<void>('writeBytes');

  @override
  Future<Result<List<VfsEntry>>> list(
    String path, {
    bool recursive = false,
  }) async => _unsupported<List<VfsEntry>>('list');

  @override
  Future<Result<void>> createDirectory(
    String path, {
    bool recursive = false,
  }) async => _unsupported<void>('createDirectory');

  @override
  Future<Result<void>> delete(String path, {bool recursive = false}) async =>
      _unsupported<void>('delete');

  Result<T> _unsupported<T>(String operation) => Err<T>(
    _problem(
      PortErrorCode.unsupported,
      operation,
      'not implemented in this fake',
    ),
  );
}

Problem _problem(PortErrorCode code, String operation, String message) =>
    portProblem(
      port: PortName.vfs,
      code: code,
      operation: operation,
      message: message,
    );

/// A minimal `key=value` layer reader, so the suite tests the LADDER rather than
/// a parser. `diene_core_utils` ships no parser by design.
Result<JsonObject> _parseKeyValue(String text) {
  final JsonObject parsed = <String, Object?>{};
  for (final String line in text.split('\n')) {
    if (line.trim().isEmpty) {
      continue;
    }
    final int equals = line.indexOf('=');
    if (equals < 1) {
      return Err<JsonObject>(
        utilProblem(
          util: UtilName.vfs,
          code: UtilErrorCode.invalidFormat,
          operation: 'parseKeyValue',
          message: 'malformed key=value line',
          details: <String, Object?>{'line': line},
        ),
      );
    }
    parsed[line.substring(0, equals)] = line.substring(equals + 1);
  }
  return Ok<JsonObject>(parsed);
}

String _describe(Result<Object?> result) => result.match(
  ok: (Object? value) => 'ok($value)',
  err: (Problem problem) => 'err(${problem.title}: ${problem.detail})',
);
