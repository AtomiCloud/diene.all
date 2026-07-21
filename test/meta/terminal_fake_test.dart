import 'package:diene_interfaces/diene_interfaces.dart';
import 'package:diene_interfaces/test_helper.dart';
import 'package:diene_result/diene_result.dart';
import 'package:test/test.dart';

import '../support/result_expectations.dart';

void main() {
  group('InMemoryTerminal', () {
    test('returns scripted output and records command identity', () async {
      // Arrange.
      const Success<TerminalOutput> response = Success<TerminalOutput>(
        TerminalOutput(exitCode: 0, stdout: 'done', stderr: ''),
      );
      final InMemoryTerminal terminal = InMemoryTerminal()..enqueue(response);
      final TerminalCommand command = TerminalCommand(
        executable: 'tool',
        arguments: const <String>['run'],
      );

      // Act.
      final Result<TerminalOutput> result = await terminal.run(command);

      // Assert.
      expect(result, same(response));
      expect(terminal.commands, <TerminalCommand>[command]);
    });

    test(
      'returns a failure rather than throwing when no result is scripted',
      () async {
        // Arrange.
        final InMemoryTerminal terminal = InMemoryTerminal();

        // Act.
        final Result<TerminalOutput> result = await terminal.run(
          TerminalCommand(executable: 'unscripted'),
        );

        // Assert.
        expect(
          expectFailure(result).data['id'],
          'terminal-result-not-scripted',
        );
      },
    );
  });
}
