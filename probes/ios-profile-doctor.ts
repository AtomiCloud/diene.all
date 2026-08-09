import { commandGate } from './lib/flutter.ts';

export default commandGate({
  feature: 'ios-profile-doctor',
  description: 'The fetched-profile doctor requires the signed App Group.',
  command: 'nix develop .#ci -c ./scripts/validate/signing-doctors.sh',
  file: 'scripts/ci/doctor-ios.sh',
  find: 'expected_group="group.${targets%%$\'\\n\'*}"',
  replace: 'expected_group="group.invalid.fixture"',
});
