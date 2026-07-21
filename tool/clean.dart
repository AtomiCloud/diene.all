import 'dart:io';

Future<void> main() async {
  for (final String path in <String>['coverage', '.dart_tool']) {
    final Directory directory = Directory(path);
    if (directory.existsSync()) {
      await directory.delete(recursive: true);
    }
  }
}
