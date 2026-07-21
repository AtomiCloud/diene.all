import { commandGate } from './lib/flutter.ts';

export default commandGate({
  feature: 'locale-switch',
  description: 'Changing locale re-renders translated Flutter widgets.',
  command:
    "nix develop .#ci -c flutter test test/widget_test.dart --plain-name 'locale and runtime color changes rebuild the shipped app'",
  file: 'lib/config/app_settings_controller.dart',
  find: 'await LocaleSettings.setLocaleRaw(value.languageCode);',
  replace: '// Locale propagation intentionally removed.',
});
