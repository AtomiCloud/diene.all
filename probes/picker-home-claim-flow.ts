import { commandGate } from './lib/flutter.ts';

export default commandGate({
  feature: 'picker-home-claim-flow',
  description: 'An existing home claim skips the picker; an absent one runs it and writes the claim.',
  command: "nix develop .#ci -c flutter test test/picker_test.dart --plain-name 'picker / home-claim flow'",
  file: 'lib/onboarding/home_claim.dart',
  // Show the picker despite an existing claim — the exact sabotage the goal
  // table names for this row.
  find: 'if (existing != null && existing.isNotEmpty) {',
  replace: 'if (false) {',
});
