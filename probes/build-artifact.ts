import { expectGreen } from './lib/helpers.ts';

export default {
  contractVersion: 1,
  sandbox: { snapshot: 'git', preserve: ['.direnv'] },
  probes: [
    {
      name: 'baseline-build-artifact-green',
      description: 'The build task emits an executable that performs a real command.',
      kind: 'baseline',
      async run(repo: any) {
        await expectGreen(
          repo,
          'nix develop .#ci -c bash -lc \'task build && test -x dist/go-base && test "$(./dist/go-base slug Diene)" = diene\'',
          'build-artifact',
        );
      },
    },
  ],
};
