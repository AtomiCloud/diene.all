import { commandGate } from './lib/flutter.ts';

export default commandGate({
  feature: 'app-handoff-legal-step',
  description: 'The legal/consent step precedes onboarding on every handoff arrival.',
  command: 'nix develop .#ci -c flutter test test/app_handoff_test.dart',
  file: 'lib/auth/app_handoff.dart',
  // Bypass the legal step by neutralising the declined-consent gate.
  //
  // NOT anchored to `assertLegalPrecedesOnboarding(...)`: removing that call
  // alone was MEASURED green (rc=0, 10 passed), because the `consent == null`
  // early return still blocks onboarding on its own. The assert is a second,
  // redundant guard, so deleting it is not a meaningful sabotage. Neutralising
  // the gate itself is one fault and lets a declined legal step through.
  find: 'if (consent == null) {',
  replace: 'if (false) {',
});
