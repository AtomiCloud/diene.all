import 'dart:io';

const double _minimumCoverage = 95;

void main(List<String> arguments) {
  if (arguments.length != 1) {
    stderr.writeln('usage: dart run tool/check_coverage.dart <lcov.info>');
    exitCode = 64;
    return;
  }

  final File report = File(arguments.single);
  if (!report.existsSync()) {
    stderr.writeln('coverage report does not exist: ${report.path}');
    exitCode = 1;
    return;
  }

  int found = 0;
  int hit = 0;
  for (final String line in report.readAsLinesSync()) {
    if (line.startsWith('LF:')) {
      found += int.parse(line.substring(3));
    } else if (line.startsWith('LH:')) {
      hit += int.parse(line.substring(3));
    }
  }
  if (found == 0) {
    stderr.writeln('coverage report contains no executable lines');
    exitCode = 1;
    return;
  }

  final double percentage = hit * 100 / found;
  stdout.writeln(
    'targeted unit coverage: $hit/$found (${percentage.toStringAsFixed(2)}%)',
  );
  if (percentage < _minimumCoverage) {
    stderr.writeln('coverage is below ${_minimumCoverage.toStringAsFixed(0)}%');
    exitCode = 1;
  }
}
