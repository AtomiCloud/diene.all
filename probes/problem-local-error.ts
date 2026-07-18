import { commandGate } from './lib/flutter.ts';

export default commandGate({
  feature: 'problem-local-error',
  description: 'Unexpected exceptions become copyable Problems and reach the injected sink.',
  command:
    "nix develop .#ci -c flutter test test/core_test.dart test/widget_test.dart --plain-name 'LocalError|ProblemVisualizer'",
  file: 'lib/core/local_error.dart',
  find: 'await sink.capture(problem);',
  replace: '// Error sink propagation intentionally removed.',
});
