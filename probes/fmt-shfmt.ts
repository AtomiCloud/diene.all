import { expectGreen, expectRedBecause } from './lib/helpers.ts';

// Fixture owned by the fmt-shfmt mutation arm: written, staged and removed inside it,
// never committed. The padding before the terminating semicolon is the whole sabotage;
// the file is otherwise ordinary, shellcheck-clean shell so that only shfmt objects.
const shfmtSubject = 'probe-fmt-shfmt.sh';
const shfmtSubjectBody = `#!/usr/bin/env bash
set -euo pipefail

if [ -n "$HOME" ]  ; then
  echo "fmt-shfmt probe subject"
fi
`;

export default {
  contractVersion: 1,
  sandbox: { snapshot: 'git', preserve: ['.direnv'] },
  probes: [
    {
      name: 'baseline-fmt-shfmt-green',
      description: 'The treefmt shfmt member passes on tracked shell scripts.',
      kind: 'baseline',
      async run(repo: any) {
        await expectGreen(repo, 'nix fmt --no-write-lock-file -- --ci --formatters shfmt', 'fmt-shfmt');
      },
    },
    {
      name: 'mutation-fmt-shfmt-caught',
      description: 'A focused sabotage must turn the fmt-shfmt mechanism red.',
      kind: 'mutation',
      expectedImpact: [],
      async run(repo: any) {
        // The sabotage is semantically identical shell - padding before a compound
        // command's terminating `;`, which shfmt removes under the treefmt member's
        // `-i 2 -s`, so only the formatter can object to it. Two earlier subjects were
        // chosen for a `case` block and then lost it, and the replacement was chosen
        // because it "could not be lost" - a criterion that has since failed again. The
        // arm writes its own subject instead, and carries the punctuation it depends on
        // rather than hoping a repository file still has it.
        await repo.write(shfmtSubject, shfmtSubjectBody);
        try {
          const staged = await repo.exec(`git add ${shfmtSubject}`);
          if (staged.exitCode !== 0) {
            throw new Error(`could not stage the shfmt fixture: ${staged.stderr || staged.stdout}`);
          }
          // The refusal must name the fixture, not merely be nonzero: an absent subject
          // and a formatter that objected are both nonzero, and only the reason separates
          // them.
          await expectRedBecause(repo, 'nix fmt --no-write-lock-file -- --ci --formatters shfmt', 'fmt-shfmt', [
            shfmtSubject,
            'unexpected changes detected',
          ]);
        } finally {
          await repo.exec(`git reset -q -- ${shfmtSubject}`);
          await repo.remove(shfmtSubject);
        }
      },
    },
  ],
};
