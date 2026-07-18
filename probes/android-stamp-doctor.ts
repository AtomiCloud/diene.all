import { commandGate } from './lib/flutter.ts';

export default commandGate({
  feature: 'android-stamp-doctor',
  description: 'The Android stamp retains bundle, identity, version, config, and signature assertions.',
  command: 'nix develop .#ci -c ./scripts/validate/signing-doctors.sh',
  file: 'scripts/ci/stamp-android.sh',
  find: 'bundletool validate --bundle="$OUT" >/dev/null',
  replace: 'true # bundle validation removed',
});
