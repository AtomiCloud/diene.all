import { expectGreen } from './lib/helpers.ts';

const gate = 'nix develop --no-write-lock-file .#ci -c pre-commit run a-markdownlint --all-files';

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
      name: 'baseline-docs-markdownlint-green',
      description: 'Markdownlint accepts the complete standards and skill-trigger payload.',
      kind: 'baseline',
      async run(repo: any) {
        await expectGreen(repo, gate, 'docs-markdownlint');
      },
    },
    {
      name: 'mutation-docs-markdownlint-caught',
      description: 'A second top-level heading must be refused as MD025, not merely fail.',
      kind: 'mutation',
      expectedImpact: [],
      async run(repo: any) {
        const path = 'docs/standards/authorization/index.md';
        const original = await repo.read(path);
        try {
          await repo.write(path, `${original}\n# Duplicate authorization title\n`);
          await expectRedFor(repo, gate, 'docs-markdownlint', path, 'MD025/single-title/single-h1');
        } finally {
          await repo.write(path, original);
        }
      },
    },
  ],
};
