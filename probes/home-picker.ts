import { commandGate } from './lib/flutter.ts';

export default commandGate({
  feature: 'home-picker',
  description: 'Every sign-in checks the home claim and single-region pass-through reaches onboarding.',
  command: 'nix develop .#ci -c flutter test test/auth_onboarding_test.dart',
  file: 'lib/onboarding/onboarding.dart',
  find: 'final Result<String> home = await homePicker.resolve();',
  replace: "const Result<String> home = Success<String>('skipped');",
});
