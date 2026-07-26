// Contract-parity tier: ONE shared behavioural suite is applied to each fake.
//
// The family meta rule asks for a shared behavioural suite run against BOTH the
// real implementation and the fake. `diene_interfaces` ships NO real
// implementation on purpose — it is the seam package, and the concrete
// `dart:io`/Flutter adapters live downstream (see doc/interfaces.md, S33
// extraction boundary). So the parity subject here is the CONTRACT ITSELF: the
// behaviour every implementation, real or fake, must exhibit. Downstream
// adapters re-run this same suite against their real implementation.

import 'package:diene_interfaces/diene_interfaces.dart';
import 'package:diene_interfaces/test_helper.dart';
import 'package:diene_result/diene_result.dart';
import 'package:diene_result/test_helper.dart';
import 'package:test/test.dart';

/// Behaviour every [System] implementation must exhibit.
void systemContract(String label, System Function() build) {
  group('System contract ($label)', () {
    test('an absent variable is Ok(null), never a failure', () {
      // Arrange & Act & Assert.
      expect(expectOk(build().environment('__DIENE_ABSENT__')), isNull);
    });

    test('the clock always answers in UTC', () {
      // Arrange & Act & Assert.
      expect(expectOk(build().nowUtc()).isUtc, isTrue);
    });

    test('the working directory is absolute', () {
      // Arrange & Act & Assert.
      expect(expectOk(build().currentDirectory()), startsWith('/'));
    });

    test('a zero delay completes', () async {
      // Arrange & Act & Assert.
      expectOk(await build().delay(Duration.zero));
    });
  });
}

/// Behaviour every [Vfs] implementation must exhibit.
void vfsContract(String label, Vfs Function() build) {
  group('Vfs contract ($label)', () {
    test('a missing path is a not-found VALUE, never a throw', () async {
      // Arrange & Act & Assert.
      expectPortProblem(
        expectErr(await build().readText('/__diene_absent__')),
        port: PortName.vfs,
        code: PortErrorCode.notFound,
      );
    });

    test(
      'exists answers false for a missing path rather than failing',
      () async {
        // Arrange & Act & Assert.
        expect(expectOk(await build().exists('/__diene_absent__')), isFalse);
      },
    );

    test('a written file reads back byte-identically', () async {
      // Arrange.
      final Vfs vfs = build();

      // Act.
      expectOk(await vfs.writeText('/parity.txt', 'round trip'));

      // Assert.
      expect(expectOk(await vfs.readText('/parity.txt')), 'round trip');
      expect(expectOk(await vfs.stat('/parity.txt')).type, VfsEntryType.file);
    });

    test('a directory created recursively becomes listable', () async {
      // Arrange.
      final Vfs vfs = build();

      // Act.
      expectOk(await vfs.createDirectory('/deep/tree', recursive: true));

      // Assert.
      expect(expectOk(await vfs.list('/deep')), hasLength(1));
    });
  });
}

/// Behaviour every [Terminal] implementation must exhibit.
void terminalContract(String label, Terminal Function() build) {
  group('Terminal contract ($label)', () {
    test(
      'a non-zero exit is captured output, not a transport failure',
      () async {
        // Arrange.
        final Terminal terminal = build();

        // Act.
        final Result<TerminalOutput> result = await terminal.run(
          TerminalCommand(executable: '__diene_nonzero__'),
        );

        // Assert.
        expect(expectOk(result).succeeded, isFalse);
      },
    );

    test('a write succeeds on both channels', () async {
      // Arrange.
      final Terminal terminal = build();

      // Act & Assert.
      for (final TerminalChannel channel in TerminalChannel.values) {
        expectOk(
          await terminal.write(TerminalWrite(channel: channel, text: 'parity')),
        );
      }
    });

    test('reading past the end of input is Ok(null)', () async {
      // Arrange & Act & Assert.
      expect(expectOk(await build().readLine()), isNull);
    });
  });
}

/// Behaviour every [LoggerSink] implementation must exhibit.
void loggerContract(String label, LoggerSink Function() build) {
  group('LoggerSink contract ($label)', () {
    test('a valid record is accepted and flushing succeeds', () async {
      // Arrange.
      final LoggerSink sink = build();

      // Act.
      expectOk(
        sink.emit(
          LogRecord(
            timestamp: DateTime.utc(2026),
            level: LogLevel.info,
            message: 'parity',
          ),
        ),
      );

      // Assert.
      expectOk(await sink.flush());
    });
  });
}

/// Behaviour every [MetricsCollector] implementation must exhibit.
void metricsContract(String label, MetricsCollector Function() build) {
  group('MetricsCollector contract ($label)', () {
    test('a valid sample is accepted and flushing succeeds', () async {
      // Arrange.
      final MetricsCollector collector = build();

      // Act.
      expectOk(
        collector.emit(
          MetricRecord(
            timestamp: DateTime.utc(2026),
            name: 'parity.total',
            kind: MetricKind.counter,
            value: 1,
          ),
        ),
      );

      // Assert.
      expectOk(await collector.flush());
    });
  });
}

void main() {
  systemContract('InMemorySystem', InMemorySystem.new);
  vfsContract('InMemoryVfs', InMemoryVfs.new);
  terminalContract(
    'InMemoryTerminal',
    () => InMemoryTerminal()
      ..enqueue(
        const Ok<TerminalOutput>(
          TerminalOutput(exitCode: 1, stdout: '', stderr: 'nonzero'),
        ),
      ),
  );
  loggerContract('InMemoryLoggerSink', InMemoryLoggerSink.new);
  metricsContract('InMemoryMetricsCollector', InMemoryMetricsCollector.new);
}
