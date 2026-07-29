import { commandGate } from './lib/flutter.ts';

export default commandGate({
  feature: 'temporal-codecs',
  description: 'Temporal domain values round-trip through C0 codecs.',
  command: "nix develop .#ci -c flutter test test/core_test.dart --plain-name 'Temporal C0 codecs'",
  file: 'lib/core/temporal.dart',
  find: 'String encodeDate(LocalDate value) => value.toString();',
  replace: "String encodeDate(LocalDate value) => 'broken';",
});
