import { expectGreen, expectRed } from './lib/helpers.ts';

export default {
  contractVersion: 1,
  sandbox: { snapshot: 'git', preserve: ['.direnv'] },
  probes: [
    {
      name: 'baseline-releaser-bootstrap-green',
      description:
        'The .#releaser shell exposes an executable named releaser (the C2 sg bootstrap) that answers the release subcommand invoked by scripts/ci/release.sh.',
      kind: 'baseline',
      async run(repo: any) {
        await expectGreen(
          repo,
          "nix develop --no-write-lock-file .#releaser -c bash -c 'command -v releaser && releaser release --help'",
          'releaser-bootstrap',
        );
      },
    },
    {
      name: 'mutation-releaser-bootstrap-caught',
      description:
        'Renaming the bootstrap binary away from releaser must drop it from the .#releaser PATH, exactly reproducing the RB-339 command-not-found failure.',
      kind: 'mutation',
      expectedImpact: [],
      async run(repo: any) {
        const source = await repo.read('nix/packages.nix');
        await repo.write(
          'nix/packages.nix',
          source.replace('writeShellScriptBin "releaser"', 'writeShellScriptBin "releaser-DISABLED"'),
        );
        await expectRed(
          repo,
          "nix develop --no-write-lock-file .#releaser -c bash -c 'command -v releaser'",
          'releaser-bootstrap',
        );
      },
    },
  ],
};
