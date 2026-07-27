import { commandGate } from './lib/flutter.ts';

export default commandGate({
  feature: 'picker-home-claim-flow',
  description: 'An existing home claim skips the picker; an absent one runs it and writes the claim.',
  command: "nix develop .#ci -c flutter test test/picker_test.dart --plain-name 'picker / home-claim flow'",
  file: 'lib/onboarding/home_claim.dart',
  // Show the picker despite an existing claim — the sabotage the goal table
  // names for this row.
  //
  // The emptiness test is inverted rather than replaced with `if (false)`. The
  // latter was MEASURED to redden only through a COMPILE error (`String?` cannot
  // be assigned to `String` at home_claim.dart:115, because the null-check no
  // longer promotes `existing`). PROBES.md §2 excludes faults that merely break
  // the subject, and a compile failure also takes down every OTHER feature
  // sharing this test file, reporting as `control_failed` rather than as this
  // row's own red. Keeping the null-check preserves promotion, so the mutation
  // compiles and a real existing claim falls through to the picker — which is
  // the behaviour under test.
  find: 'if (existing != null && existing.isNotEmpty) {',
  replace: 'if (existing != null && existing.isEmpty) {',
});
