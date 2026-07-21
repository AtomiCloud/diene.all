import { commandGate } from './lib/flutter.ts';

export default commandGate({
  feature: 'android-workflow-wiring',
  description: 'The Android donor/publish workflows resolve to valid keystore scripts.',
  command:
    "nix develop .#ci -c bash -c './scripts/validate/workflows.sh wiring && ./scripts/validate/mobile-workflows.sh'",
  file: '.github/workflows/⚡reusable-publish-android.yaml',
  find: './scripts/ci/publish-android.sh',
  replace: './scripts/ci/publish-android-missing.sh',
});
