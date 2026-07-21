import { commandGate } from './lib/flutter.ts';

export default commandGate({
  feature: 'flutter-analyze-hook',
  description: 'Flutter analyzer runs through the declared source surface.',
  command: 'nix develop .#ci -c flutter analyze',
  file: 'lib/core/result.dart',
  find: 'bool get isSuccess => this is Success<T>;',
  replace: 'bool get isSuccess => missingAnalyzerSymbol;',
});
