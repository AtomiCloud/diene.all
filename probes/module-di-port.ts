import { commandGate } from './lib/flutter.ts';

export default commandGate({
  feature: 'module-di-port',
  description: 'The provider resolves every registered module binding, lazily and once.',
  command: 'nix develop .#ci -c flutter test test/di_module_test.dart',
  file: 'lib/di/module.dart',
  // Break one registration lookup: every binding now reads as missing, so the
  // resolve-succeeds cases go red while the total-function contract holds.
  find: 'final _Binding? binding = _bindings[T];',
  replace: 'const _Binding? binding = null;',
});
