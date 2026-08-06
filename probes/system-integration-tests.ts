import { expectGreen } from './lib/helpers.ts';

// The CI system-integration lane is self-contained: it sets the repository up and runs the compiled artifact against a real Redis.
const gate = 'nix develop .#ci -c ./scripts/ci/sit.sh';
const gateTimeoutMs = 600000;

export default {
  contractVersion: 1,
  sandbox: { snapshot: 'git', preserve: ['.direnv'] },
  probes: [
    {
      name: 'baseline-system-integration-tests-green',
      description: 'The CI system-integration entrypoint builds the artifact and completes the tier on its own.',
      kind: 'baseline',
      async run(repo: any) {
        await expectGreen(repo, gate, 'system-integration-tests', gateTimeoutMs);
      },
    },
  ],
};
