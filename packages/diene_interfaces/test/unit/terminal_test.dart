import 'package:diene_interfaces/diene_interfaces.dart';
import 'package:diene_problems/diene_problems.dart';
import 'package:diene_result/test_helper.dart';
import 'package:test/test.dart';

final String _nul = String.fromCharCode(0);

void main() {
  group('TerminalCommand', () {
    test('copies and freezes its arguments and environment', () {
      // Arrange.
      final List<String> arguments = <String>['--version'];
      final Map<String, String> environment = <String, String>{'LC_ALL': 'C'};

      // Act.
      final TerminalCommand command = TerminalCommand(
        executable: 'git',
        arguments: arguments,
        environment: environment,
        workingDirectory: '/repo',
        includeParentEnvironment: false,
        runInShell: true,
      );
      arguments.add('--mutated');
      environment['INJECTED'] = '1';

      // Assert.
      expect(command.arguments, <String>['--version']);
      expect(command.environment, <String, String>{'LC_ALL': 'C'});
      expect(() => command.arguments.add('x'), throwsUnsupportedError);
      expect(() => command.environment['x'] = 'y', throwsUnsupportedError);
      expect(command.workingDirectory, '/repo');
      expect(command.includeParentEnvironment, isFalse);
      expect(command.runInShell, isTrue);
      expect(command.toString(), 'TerminalCommand(git --version)');
    });

    test('defaults to an inherited environment and no shell', () {
      // Arrange & Act.
      final TerminalCommand command = TerminalCommand(executable: 'ls');

      // Assert.
      expect(command.arguments, isEmpty);
      expect(command.environment, isEmpty);
      expect(command.workingDirectory, isNull);
      expect(command.includeParentEnvironment, isTrue);
      expect(command.runInShell, isFalse);
    });
  });

  group('TerminalOutput', () {
    test('reports success only for a zero exit code', () {
      // Arrange & Act.
      const TerminalOutput ok = TerminalOutput(
        exitCode: 0,
        stdout: 'out',
        stderr: '',
      );
      const TerminalOutput failed = TerminalOutput(
        exitCode: 1,
        stdout: '',
        stderr: 'err',
      );

      // Assert.
      expect(ok.succeeded, isTrue);
      expect(ok.stdout, 'out');
      expect(failed.succeeded, isFalse);
      expect(failed.stderr, 'err');
      expect(failed.toString(), 'TerminalOutput(1)');
    });
  });

  group('TerminalWrite and TerminalRead', () {
    test('a write defaults to a trailing newline', () {
      // Arrange & Act.
      const TerminalWrite write = TerminalWrite(
        channel: TerminalChannel.stderr,
        text: 'boom',
      );

      // Assert.
      expect(write.channel, TerminalChannel.stderr);
      expect(write.newline, isTrue);
      expect(write.toString(), 'TerminalWrite(stderr, 4 chars)');
      expect(TerminalChannel.values, hasLength(2));
    });

    test('a read carries an optional prompt', () {
      // Arrange & Act.
      const TerminalRead read = TerminalRead(prompt: 'name? ');

      // Assert.
      expect(read.prompt, 'name? ');
      expect(read.toString(), 'TerminalRead(name? )');
      expect(const TerminalRead().prompt, isNull);
    });
  });

  group('checkTerminalCommand', () {
    test('accepts a well-formed invocation', () {
      // Arrange.
      final TerminalCommand command = TerminalCommand(
        executable: 'git',
        arguments: <String>['status'],
        environment: <String, String>{'LC_ALL': 'C'},
      );

      // Act & Assert.
      expect(expectOk(checkTerminalCommand(command)), same(command));
    });

    test('rejects a blank executable', () {
      // Arrange & Act.
      final Problem problem = expectErr(
        checkTerminalCommand(TerminalCommand(executable: '  ')),
      );

      // Assert.
      expect(problem.data['field'], 'executable');
      expect(problem.title, 'Executable must be non-blank');
    });

    test('rejects a NUL-bearing executable', () {
      // Arrange & Act.
      final Problem problem = expectErr(
        checkTerminalCommand(TerminalCommand(executable: 'g${_nul}it')),
      );

      // Assert.
      expect(problem.title, 'Executable must not contain a NUL byte');
    });

    test('rejects a NUL-bearing argument', () {
      // Arrange & Act.
      final Problem problem = expectErr(
        checkTerminalCommand(
          TerminalCommand(
            executable: 'git',
            arguments: <String>['ok', 'ba${_nul}d'],
          ),
        ),
      );

      // Assert.
      expect(problem.data['field'], 'arguments');
    });

    test('rejects a blank environment name', () {
      // Arrange & Act.
      final Problem problem = expectErr(
        checkTerminalCommand(
          TerminalCommand(
            executable: 'git',
            environment: <String, String>{' ': 'x'},
          ),
        ),
      );

      // Assert.
      expect(problem.data['field'], 'environment');
    });

    test('rejects an environment name containing an equals sign', () {
      // Arrange & Act.
      final Problem problem = expectErr(
        checkTerminalCommand(
          TerminalCommand(
            executable: 'git',
            environment: <String, String>{'A=B': 'x'},
          ),
        ),
      );

      // Assert.
      expect(
        problem.title,
        'Environment names must be non-blank and free of "="',
      );
    });
  });

  group('checkTerminalOutput', () {
    test('accepts an in-range exit code', () {
      // Arrange.
      const TerminalOutput output = TerminalOutput(
        exitCode: 255,
        stdout: '',
        stderr: '',
      );

      // Act & Assert.
      expect(expectOk(checkTerminalOutput(output)), same(output));
    });

    test('rejects a negative exit code', () {
      // Arrange & Act.
      final Problem problem = expectErr(
        checkTerminalOutput(
          const TerminalOutput(exitCode: -1, stdout: '', stderr: ''),
        ),
      );

      // Assert.
      expect(problem.data['field'], 'exitCode');
    });

    test('rejects an out-of-range exit code', () {
      // Arrange & Act & Assert.
      expect(
        expectErr(
          checkTerminalOutput(
            const TerminalOutput(exitCode: 256, stdout: '', stderr: ''),
          ),
        ).title,
        'Exit code must be within 0..255',
      );
    });
  });

  group('checkTerminalWrite and checkTerminalRead', () {
    test('accept clean payloads', () {
      // Arrange & Act & Assert.
      expect(
        expectOk(
          checkTerminalWrite(
            const TerminalWrite(channel: TerminalChannel.stdout, text: 'hi'),
          ),
        ).text,
        'hi',
      );
      expect(expectOk(checkTerminalRead(const TerminalRead())).prompt, isNull);
      expect(
        expectOk(checkTerminalRead(const TerminalRead(prompt: 'go'))).prompt,
        'go',
      );
    });

    test('reject NUL-bearing payloads', () {
      // Arrange & Act.
      final Problem writeProblem = expectErr(
        checkTerminalWrite(
          TerminalWrite(channel: TerminalChannel.stdout, text: 'a${_nul}b'),
        ),
      );
      final Problem readProblem = expectErr(
        checkTerminalRead(TerminalRead(prompt: 'a${_nul}b')),
      );

      // Assert.
      expect(writeProblem.data['field'], 'text');
      expect(readProblem.data['field'], 'prompt');
    });
  });
}
