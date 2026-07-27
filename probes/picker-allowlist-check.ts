import { commandGate } from './lib/flutter.ts';

export default commandGate({
  feature: 'picker-allowlist-check',
  description: 'Discovery documents and derived ping URLs must sit on a baked endpoint suffix.',
  command: "nix develop .#ci -c flutter test test/picker_test.dart --plain-name 'allowlist'",
  file: 'lib/onboarding/picker.dart',
  // Sabotage the LOGIC, not the naming: reintroducing the plain DNS-name
  // accessor would also trip a-flutter-landscape-policy and muddy attribution.
  find: "uri.scheme == 'https' && allowsAuthority(authorityName(uri));",
  replace: 'true;',
});
