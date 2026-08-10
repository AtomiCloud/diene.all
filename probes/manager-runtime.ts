import { expectGreen } from './lib/helpers.ts';

export default {
  contractVersion: 1,
  sandbox: { snapshot: 'git', preserve: ['.direnv'] },
  probes: [
    {
      name: 'baseline-manager-runtime-green',
      description: 'The built manager starts against envtest and answers /healthz and /readyz.',
      kind: 'baseline',
      async run(repo: any) {
        await expectGreen(
          repo,
          'nix develop .#ci -c bash -lc \'./scripts/local/build.sh && MANAGER_BINARY="$PWD/dist/manager" go test -count=1 -run "^TestManagerRuntimeHealthEndpoints$" ./tests/int/operator/\'',
          'manager-runtime',
        );
      },
    },
  ],
};
