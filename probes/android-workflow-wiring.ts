import { commandGate } from './lib/flutter.ts';

export default commandGate({
  feature: 'android-workflow-wiring',
  description: 'The Android publish workflow carries the keystore-base64 signing contract.',
  command:
    "nix develop .#ci -c bash -c './scripts/validate/workflows.sh wiring && ./scripts/validate/mobile-workflows.sh'",
  file: '.github/workflows/⚡reusable-publish-android.yaml',
  find: 'ANDROID_KEYSTORE_BASE64: ${{ secrets.ANDROID_KEYSTORE_BASE64 }}',
  replace: 'ANDROID_KEYSTORE_ABSENT: ${{ secrets.ANDROID_KEYSTORE_ABSENT }}',
});
