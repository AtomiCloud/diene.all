import { commandGate } from './lib/flutter.ts';

export default commandGate({
  feature: 'ios-stamp-doctor',
  description: 'The iOS stamp retains signature, identity, entitlement, config, and packing assertions.',
  command: 'nix develop .#ci -c ./scripts/validate/signing-doctors.sh',
  file: 'scripts/ci/stamp-ios.sh',
  find: 'codesign --verify --deep --strict "${app}"',
  replace: 'true # codesign verification removed',
});
