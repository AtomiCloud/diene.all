import { expectGreen } from './lib/helpers.ts';

const gate =
  'nix fmt --no-write-lock-file -- docs/standards .claude/skills CLAUDE.md README.md --ci --formatters prettier';

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
      name: 'baseline-docs-prettier-green',
      description: 'Prettier accepts the complete standards, skill, and index-pointer payload.',
      kind: 'baseline',
      async run(repo: any) {
        await expectGreen(repo, gate, 'docs-prettier');
      },
    },
    {
      name: 'mutation-docs-prettier-caught',
      description: 'Misaligned skill frontmatter must be refused as an unformatted file, not merely fail.',
      kind: 'mutation',
      expectedImpact: ['fmt-prettier', 'precommit-treefmt-prettier'],
      async run(repo: any) {
        const path = '.claude/skills/authorization/SKILL.md';
        const original = await repo.read(path);
        try {
          await repo.patch(path, { find: 'name: authorization', replace: 'name:    authorization' });
          await expectRedFor(repo, gate, 'docs-prettier', path, 'unexpected changes detected');
        } finally {
          // treefmt rewrites in place even under --ci, so the restore is load-bearing.
          await repo.write(path, original);
        }
      },
    },
  ],
};
