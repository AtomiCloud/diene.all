import { expectGreen, expectRedWithDiagnostic } from './lib/helpers.ts';

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
      description: 'A lowercase indented root override after the valid declaration must turn the nonroot policy red.',
      kind: 'mutation',
      async run(repo: any) {
        const original = await repo.read('infra/Dockerfile');
        try {
          // Leave the compliant declaration in place: the effective user is the last one Docker reads, case-insensitively and indented.
          await repo.patch('infra/Dockerfile', {
            find: 'USER 65532:65532\n',
            replace: 'USER 65532:65532\n  user 0:0\n',
          });
          await expectRedWithDiagnostic(
            repo,
            'nix develop .#ci -c ./scripts/validate/go-image-policy.sh nonroot',
            'nonroot-image-policy',
            /final runtime image must run as 65532:65532/,
          );
        } finally {
          await repo.write('infra/Dockerfile', original);
        }
      },
    },
  ],
};
