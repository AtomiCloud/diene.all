import 'package:diene_interfaces/diene_interfaces.dart';
import 'package:diene_interfaces/test_helper.dart';
import 'package:diene_result/diene_result.dart';
import 'package:diene_result/test_helper.dart';
import 'package:test/test.dart';

void main() {
  group('InMemoryTerminal.run', () {
    test('records commands and serves scripted outputs FIFO', () async {
      // Arrange.
      final InMemoryTerminal terminal = InMemoryTerminal()
        ..enqueue(
          const Ok<TerminalOutput>(
            TerminalOutput(exitCode: 0, stdout: 'first', stderr: ''),
          ),
        )
        ..enqueue(
          const Ok<TerminalOutput>(
            TerminalOutput(exitCode: 2, stdout: '', stderr: 'usage'),
          ),
        );

      // Act.
      final TerminalOutput first = expectOk(
        await terminal.run(TerminalCommand(executable: 'git')),
      );
      final TerminalOutput second = expectOk(
        await terminal.run(
          TerminalCommand(executable: 'git', arguments: <String>['bogus']),
        ),
      );

      // Assert.
      expect(first.stdout, 'first');
      expect(second.exitCode, 2);
      expect(
        second.succeeded,
        isFalse,
        reason: 'captured, not a transport failure',
      );
      expect(
        terminal.commands.map((TerminalCommand command) => command.executable),
        <String>['git', 'git'],
      );
      expect(terminal.commands.last.arguments, <String>['bogus']);
    });

    test(
      'an unscripted run is an unexpected-call failure, not a throw',
      () async {
        // Arrange.
        final InMemoryTerminal terminal = InMemoryTerminal();

        // Act.
        final Object problem = expectErr(
          await terminal.run(TerminalCommand(executable: 'missing')),
        );

        // Assert.
        expect(problem, isNotNull);
        expectPortProblem(
          expectErr(await terminal.run(TerminalCommand(executable: 'missing'))),
          port: PortName.terminal,
          code: PortErrorCode.unexpectedCall,
          operation: 'run',
        );
      },
    );

    test('a scripted launch failure crosses as a value', () async {
      // Arrange.
      final InMemoryTerminal terminal = InMemoryTerminal()
        ..enqueue(
          portFailure<TerminalOutput>(
            port: PortName.terminal,
            code: PortErrorCode.permissionDenied,
            operation: 'run',
            message: 'Executable not permitted',
          ),
        );

      // Act & Assert.
      expectPortProblem(
        expectErr(await terminal.run(TerminalCommand(executable: 'sudo'))),
        port: PortName.terminal,
        code: PortErrorCode.permissionDenied,
      );
    });
  });

  group('InMemoryTerminal stdio', () {
    test('records writes and succeeds by default', () async {
      // Arrange.
      final InMemoryTerminal terminal = InMemoryTerminal();

      // Act.
      expectOk(
        await terminal.write(
          const TerminalWrite(channel: TerminalChannel.stdout, text: 'hello'),
        ),
      );
      expectOk(
        await terminal.write(
          const TerminalWrite(
            channel: TerminalChannel.stderr,
            text: 'oops',
            newline: false,
          ),
        ),
      );

      // Assert.
      expect(terminal.writes.map((TerminalWrite write) => write.text), <String>[
        'hello',
        'oops',
      ]);
      expect(terminal.writes.last.newline, isFalse);
    });

    test('scripts a write failure', () async {
      // Arrange.
      final InMemoryTerminal terminal = InMemoryTerminal()
        ..enqueueWriteResult(
          portFailure<void>(
            port: PortName.terminal,
            code: PortErrorCode.closed,
            operation: 'write',
            message: 'Stream closed',
          ),
        );

      // Act & Assert.
      expectPortProblem(
        expectErr(
          await terminal.write(
            const TerminalWrite(channel: TerminalChannel.stdout, text: 'x'),
          ),
        ),
        port: PortName.terminal,
        code: PortErrorCode.closed,
      );
      expectOk(
        await terminal.write(
          const TerminalWrite(channel: TerminalChannel.stdout, text: 'y'),
        ),
      );
    });

    test(
      'drains seeded input, then reports end of input as Ok(null)',
      () async {
        // Arrange.
        final InMemoryTerminal terminal = InMemoryTerminal(
          input: <String>['alice', 'bob'],
        );

        // Act.
        final String? first = expectOk(await terminal.readLine());
        final String? second = expectOk(
          await terminal.readLine(const TerminalRead(prompt: 'name? ')),
        );
        final String? third = expectOk(await terminal.readLine());

        // Assert.
        expect(first, 'alice');
        expect(second, 'bob');
        expect(third, isNull);
        expect(terminal.reads, hasLength(3));
        expect(terminal.reads[1].prompt, 'name? ');
      },
    );

    test('scripts a read failure', () async {
      // Arrange.
      final InMemoryTerminal terminal = InMemoryTerminal()
        ..enqueueReadResult(
          portFailure<String?>(
            port: PortName.terminal,
            code: PortErrorCode.unsupported,
            operation: 'readLine',
            message: 'Not interactive',
          ),
        );

      // Act & Assert.
      expectPortProblem(
        expectErr(await terminal.readLine()),
        port: PortName.terminal,
        code: PortErrorCode.unsupported,
      );
    });

    test('reports the configured interactivity', () {
      // Arrange & Act & Assert.
      expect(InMemoryTerminal().interactive, isTrue);
      expect(InMemoryTerminal(interactive: false).interactive, isFalse);
    });
  });
}
