import { commandGate } from './lib/flutter.ts';

export default commandGate({
  feature: 'ios-workflow-wiring',
  description: 'The iOS donor/publish workflows resolve to valid signing scripts.',
  command:
    "nix develop .#ci -c bash -c './scripts/validate/workflows.sh wiring && ./scripts/validate/mobile-workflows.sh'",
  file: '.github/workflows/⚡reusable-publish-ios.yaml',
  find: './scripts/ci/publish-ios.sh',
  replace: './scripts/ci/publish-ios-missing.sh',
});
