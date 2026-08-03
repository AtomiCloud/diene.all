import { expectGreen, expectRed } from './lib/helpers.ts';

// A script and the script it sources routinely land in different pre-commit batches,
// so the gate is only honest if it follows declared sources. The fixture below is
// healthy shell; it is checked WITHOUT its sourced sibling in the batch, which is what
// deterministic pre-commit partitioning does in practice. Bare ShellCheck raises
// SC1091 there, so this arm turns red the moment source following leaves the hook.
const sourceFixtureDir = 'probe-shellcheck-source';
const sourcedFixture = `${sourceFixtureDir}/init-state.sh`;
const repoRelativeFixture = `${sourceFixtureDir}/mark-done.sh`;
const scriptRelativeFixture = `${sourceFixtureDir}/next-file.sh`;

const sourcedBody = `#!/usr/bin/env bash
# Sourced by the sibling fixtures; declares the state they read.
set -euo pipefail

STATE_VERSION=1
`;

const sourcingBody = (directive: string) => `#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "\${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=${directive}
source "$SCRIPT_DIR/init-state.sh"

echo "📝 state version \${STATE_VERSION}"
`;

async function removeSourceFixture(repo: any): Promise<void> {
  await repo.exec(`git rm -r -f -q --cached -- ${sourceFixtureDir}`);
  await repo.exec(`git clean -fdxq -- ${sourceFixtureDir}`);
}

export default {
  contractVersion: 1,
  sandbox: { snapshot: 'git', preserve: ['.direnv'] },
  probes: [
    {
      name: 'baseline-hook-shellcheck-green',
      description: 'The generated shellcheck hook passes on the untouched scripts.',
      kind: 'baseline',
      async run(repo: any) {
        await expectGreen(repo, 'nix develop .#ci -c pre-commit run a-shellcheck --all-files', 'hook-shellcheck');
      },
    },
    {
      name: 'baseline-hook-shellcheck-follows-sources',
      description:
        'The shellcheck hook follows a declared sourced script even when the sourced file is not in the same batch, for both repository-root-relative and script-relative source directives.',
      kind: 'baseline',
      async run(repo: any) {
        await repo.write(sourcedFixture, sourcedBody);
        await repo.write(repoRelativeFixture, sourcingBody(sourcedFixture));
        await repo.write(scriptRelativeFixture, sourcingBody('init-state.sh'));
        const staged = await repo.exec(`git add ${sourceFixtureDir}`);
        if (staged.exitCode !== 0) {
          throw new Error(`could not stage the source-following fixture: ${staged.stderr || staged.stdout}`);
        }
        try {
          await expectGreen(
            repo,
            `nix develop .#ci -c pre-commit run a-shellcheck --files ${repoRelativeFixture}`,
            'hook-shellcheck',
          );
          await expectGreen(
            repo,
            `nix develop .#ci -c pre-commit run a-shellcheck --files ${scriptRelativeFixture}`,
            'hook-shellcheck',
          );
        } finally {
          await removeSourceFixture(repo);
        }
      },
    },
    {
      name: 'mutation-hook-shellcheck-caught',
      description: 'A focused sabotage must turn the hook-shellcheck mechanism red.',
      kind: 'mutation',
      expectedImpact: [],
      async run(repo: any) {
        const source = await repo.read('scripts/release/bump.sh');
        await repo.write('scripts/release/bump.sh', `${source}\necho $UNQUOTED\n`);
        await expectRed(repo, 'nix develop .#ci -c pre-commit run a-shellcheck --all-files', 'hook-shellcheck');
      },
    },
  ],
};
