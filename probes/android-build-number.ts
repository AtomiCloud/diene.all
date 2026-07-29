import { commandGate } from './lib/flutter.ts';

export default commandGate({
  feature: 'android-build-number',
  description: 'The Android build-number guard implements max(store+1, run).',
  command: 'nix develop .#ci -c ./scripts/validate/build-numbers.sh',
  file: 'scripts/ci/lib-android.sh',
  find: 'next="$((latest + 1))"',
  replace: 'next="$((latest + 2))"',
});
