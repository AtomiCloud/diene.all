import { expectGreen } from './lib/helpers.ts';

const gate = 'nix develop --no-write-lock-file .#ci -c pre-commit run a-claude-links --all-files';

// A non-zero exit only proves the gate ran badly; it does not prove it refused
// the planted fault. Each mutation therefore names the diagnostic it expects.
async function expectRedFor(repo: any, command: string, label: string, ...reasons: string[]): Promise<void> {
  const result = await repo.exec(command, { timeoutMs: 240000 });
  if (result.exitCode === 0) {
    throw new Error(`${label} stayed green after sabotage`);
  }
  const output = `${result.stdout}\n${result.stderr}`;
  const missing = reasons.filter(reason => !output.includes(reason));
  if (missing.length > 0) {
    throw new Error(`${label} went red for the wrong reason (missing: ${missing.join(', ')})\n${output}`);
  }
}

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
      name: 'mutation-claude-link-integrity-caught',
      description: 'A corrupted standard pointer must be refused as an unresolvable link, not merely fail.',
      kind: 'mutation',
      expectedImpact: [],
      async run(repo: any) {
        const path = 'CLAUDE.md';
        const original = await repo.read(path);
        try {
          await repo.patch(path, {
            find: 'docs/standards/authorization/index.md)',
            replace: 'docs/standards/authorization/missing.md)',
          });
          await expectRedFor(
            repo,
            gate,
            'claude-link-integrity',
            'docs/standards/authorization/missing.md',
            'File not found',
          );
        } finally {
          await repo.write(path, original);
        }
      },
    },
  ],
};
