import 'dart:io';

final RegExp _export = RegExp(r"^export '([^']+)';$");
final RegExp _declaration = RegExp(
  r'^(?:(?:final|sealed|abstract) class|class|enum|typedef)\s+([A-Za-z]\w*)|^(?:Future<[^>]+>|Object\?|String|bool|JsonObject|NamespacedKeyResult|DateTime)\s+([A-Za-z]\w*)\s*\(',
);

void main(List<String> arguments) {
  if (arguments.length != 1 ||
      !<String>{'--with-tests', '--production'}.contains(arguments.single)) {
    stderr.writeln(
      'usage: dart run tool/dead_code.dart --with-tests|--production',
    );
    exitCode = 64;
    return;
  }

  final File barrel = File('lib/diene_core_utils.dart');
  final Set<String> exports = <String>{};
  for (final String line in barrel.readAsLinesSync()) {
    final RegExpMatch? match = _export.firstMatch(line);
    if (match != null) {
      exports.add('lib/${match.group(1)!}');
    }
  }

  final List<File> sources = Directory('lib/src')
      .listSync()
      .whereType<File>()
      .where((File file) => file.path.endsWith('.dart'))
      .toList()
    ..sort((File left, File right) => left.path.compareTo(right.path));
  final List<String> failures = <String>[];
  for (final File source in sources) {
    if (!exports.contains(source.path)) {
      failures.add('${source.path} is unreachable from the public barrel');
    }
  }

  if (arguments.single == '--with-tests') {
    final List<File> tests = Directory('test')
        .listSync(recursive: true)
        .whereType<File>()
        .where((File file) => file.path.endsWith('.dart'))
        .toList();
    final String corpus = <File>[barrel, ...sources, ...tests]
        .map((File file) => file.readAsStringSync())
        .join('\n');
    for (final File source in sources) {
      for (final String line in source.readAsLinesSync()) {
        final RegExpMatch? match = _declaration.firstMatch(line);
        final String? name = match?.group(1) ?? match?.group(2);
        if (name == null || name.startsWith('_')) {
          continue;
        }
        final int references =
            RegExp('\\b${RegExp.escape(name)}\\b').allMatches(corpus).length;
        if (references < 2) {
          failures
              .add('$name is exported but has no test or implementation use');
        }
      }
    }
  }

  if (failures.isNotEmpty) {
    stderr.writeln(failures.join('\n'));
    exitCode = 1;
    return;
  }
  stdout.writeln('dead-code ${arguments.single} pass: clean');
}
