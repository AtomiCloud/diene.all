import { commandGate } from './lib/flutter.ts';

export default commandGate({
  feature: 'result-problem',
  description: 'Temporary C0-shaped Result and Problem copies are proven.',
  command: "nix develop .#ci -c flutter test test/core_test.dart --plain-name 'Result folds'",
  file: 'lib/core/result.dart',
  find: 'bool get isSuccess => this is Success<T>;',
  replace: 'bool get isSuccess => false;',
});
