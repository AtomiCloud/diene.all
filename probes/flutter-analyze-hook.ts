import { commandGate } from './lib/flutter.ts';

export default commandGate({
  feature: 'flutter-analyze-hook',
  description: 'Flutter analyzer runs through its generated pre-commit entrypoint.',
  command: 'nix develop .#ci -c pre-commit run a-flutter-analyze --all-files',
  file: 'lib/core/result.dart',
  find: 'bool get isSuccess => this is Success<T>;',
  replace: 'bool get isSuccess => missingAnalyzerSymbol;',
});
