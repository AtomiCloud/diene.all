import { expectGreen } from './lib/helpers.ts';

export default {
  contractVersion: 1,
  sandbox: { snapshot: 'git', preserve: ['.direnv'] },
  probes: [
    {
      name: 'baseline-build-artifact-green',
      description: 'The build task emits an executable manager that reports its interface.',
      kind: 'baseline',
      async run(repo: any) {
        await expectGreen(
          repo,
          "nix develop .#ci -c bash -lc './scripts/local/build.sh && test -x dist/manager && ./dist/manager --help 2>&1 | rg -q enable-note'",
          'build-artifact',
        );
      },
    },
  ],
};
