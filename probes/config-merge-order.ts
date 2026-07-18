import { commandGate } from './lib/flutter.ts';

export default commandGate({
  feature: 'config-merge-order',
  description: 'Configuration applies base, flavor, then compile-time overrides.',
  command: 'nix develop .#ci -c flutter test test/config_test.dart',
  file: 'lib/config/app_config.dart',
  find: 'final Map<String, Object?> merged = deepMerge(base, overlay);',
  replace: 'final Map<String, Object?> merged = deepMerge(overlay, base);',
});
