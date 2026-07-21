import { commandGate } from './lib/flutter.ts';

export default commandGate({
  feature: 'flutter-tests',
  description: 'Flutter unit and widget tests are green.',
  command: 'nix develop .#ci -c flutter test test/core_test.dart',
  file: 'test/core_test.dart',
  find: 'expect(value, 42);',
  replace: 'expect(value, 41);',
});
