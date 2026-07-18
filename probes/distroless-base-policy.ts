import { expectGreen, expectRed } from './lib/helpers.ts';

export default {
  contractVersion: 1,
  sandbox: { snapshot: 'git', preserve: ['.direnv'] },
  probes: [
    {
      name: 'baseline-distroless-policy-green',
      description: 'The runtime image uses the declared distroless base.',
      kind: 'baseline',
      async run(repo: any) {
        await expectGreen(
          repo,
          'nix develop .#ci -c ./scripts/validate/go-image-policy.sh distroless',
          'distroless-base-policy',
        );
      },
    },
    {
      name: 'mutation-distroless-policy-caught',
      description: 'Replacing the runtime with Alpine must turn the distroless policy red.',
      kind: 'mutation',
      async run(repo: any) {
        await repo.patch('infra/Dockerfile', {
          find: 'FROM gcr.io/distroless/static-debian12:nonroot AS runtime',
          replace: 'FROM alpine:3.22 AS runtime',
        });
        await expectRed(
          repo,
          'nix develop .#ci -c ./scripts/validate/go-image-policy.sh distroless',
          'distroless-base-policy',
        );
      },
    },
  ],
};
