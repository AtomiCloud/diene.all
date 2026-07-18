import { expectGreen, expectRed } from './lib/helpers.ts';

export default {
  contractVersion: 1,
  sandbox: { snapshot: 'git', preserve: ['.direnv'] },
  probes: [
    {
      name: 'baseline-nonroot-policy-green',
      description: 'The runtime image declares the unprivileged distroless identity.',
      kind: 'baseline',
      async run(repo: any) {
        await expectGreen(
          repo,
          'nix develop .#ci -c ./scripts/validate/go-image-policy.sh nonroot',
          'nonroot-image-policy',
        );
      },
    },
    {
      name: 'mutation-nonroot-policy-caught',
      description: 'Changing the runtime user to root must turn the nonroot policy red.',
      kind: 'mutation',
      async run(repo: any) {
        await repo.patch('infra/Dockerfile', { find: 'USER 65532:65532', replace: 'USER 0:0' });
        await expectRed(
          repo,
          'nix develop .#ci -c ./scripts/validate/go-image-policy.sh nonroot',
          'nonroot-image-policy',
        );
      },
    },
  ],
};
