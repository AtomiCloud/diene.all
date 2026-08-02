import { expectGreen } from './lib/helpers.ts';

const gate = 'nix develop --no-write-lock-file .#ci -c pre-commit run a-claude-links --all-files';

// The selection-sensitive invocation. Passing only the target path is what
// distinguishes always_run from the old `files` selector: under that selector this
// same command reported "(no files to check) Skipped" and never saw the broken link.
const targetOnlyGate = (path: string) =>
  `nix develop --no-write-lock-file .#ci -c pre-commit run a-claude-links --files ${path}`;

// A CLAUDE.md link target that lives outside the old selector's patterns.
const target = 'docs/domain/README.md';

export default {
  contractVersion: 1,
  sandbox: { snapshot: 'git', preserve: ['.direnv'] },
  probes: [
    {
      name: 'baseline-claude-link-integrity-green',
      description: 'Every Markdown link in CLAUDE.md resolves to its local target.',
      kind: 'baseline',
      async run(repo: any) {
        await expectGreen(repo, gate, 'claude-link-integrity');
      },
    },
    {
      name: 'mutation-claude-link-target-removal-caught',
      description:
        'Removing a CLAUDE.md link target must make the hook run and reject it, even when only that target is passed.',
      kind: 'mutation',
      expectedImpact: [],
      async run(repo: any) {
        const original = await repo.read(target);
        try {
          await repo.remove(target);
          const command = targetOnlyGate(target);
          const result = await repo.exec(command, { timeoutMs: 240000 });
          const output = `${result.stdout}\n${result.stderr}`;

          // The point of this probe: the hook must have RUN. A "Skipped" here is the
          // exact defect being guarded against, and it exits 0 — so asserting on the
          // exit code alone would report a false pass.
          if (output.includes('Skipped')) {
            throw new Error(`a-claude-links was skipped for its own link target ${target}\n${output}`);
          }
          if (result.exitCode === 0) {
            throw new Error(`a-claude-links stayed green after ${target} was removed\n${output}`);
          }
          // And it must be red for the planted reason, not for an unrelated failure.
          for (const reason of [target, 'File not found']) {
            if (!output.includes(reason)) {
              throw new Error(`a-claude-links went red for the wrong reason (missing: ${reason})\n${output}`);
            }
          }
        } finally {
          await repo.write(target, original);
        }
      },
    },
  ],
};
