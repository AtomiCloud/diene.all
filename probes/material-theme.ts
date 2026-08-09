import { commandGate } from './lib/flutter.ts';

export default commandGate({
  feature: 'material-theme',
  description: 'Material 3 light, dark, system, and identity themes are proven.',
  command: 'nix develop .#ci -c flutter test test/theme_test.dart',
  file: 'lib/theme/app_theme.dart',
  find: 'useMaterial3: true,',
  replace: 'useMaterial3: false,',
});
