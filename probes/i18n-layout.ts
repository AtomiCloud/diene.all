import { commandGate } from './lib/flutter.ts';

export default commandGate({
  feature: 'i18n-layout',
  description: 'The shipped app remains overflow-free across all locales.',
  command: "nix develop .#ci -c flutter test test/widget_test.dart --plain-name 'shipped home has no layout overflow'",
  file: 'lib/app.dart',
  find: 'constraints: const BoxConstraints(minHeight: 330),',
  replace: 'constraints: const BoxConstraints.tightFor(height: 40),',
});
