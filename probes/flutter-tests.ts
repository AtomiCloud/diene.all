import { commandGate } from './lib/flutter.ts';

export default commandGate({
  feature: 'flutter-tests',
  description: 'The complete Flutter test suite runs through its generated pre-commit entrypoint.',
  command: 'nix develop .#ci -c pre-commit run a-flutter-test --all-files',
  file: 'test/core_test.dart',
  find: 'expect(value, 42);',
  replace: 'expect(value, 41);',
});
