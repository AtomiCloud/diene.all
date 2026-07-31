const topics = [
  'authorization',
  'contributor-docs',
  'datetime',
  'domain-driven-design',
  'functional-practices',
  'software-design-philosophy',
  'solid-principles',
  'stateless-oop-di',
  'testing',
  'three-layer-architecture',
  'utilities',
  'validation',
] as const;

// The probe runtime is Bun, which ships a YAML parser as Bun.YAML.parse. A regex
// over the frontmatter would report a malformed document as proven — an
// unterminated flow value still yields a `name:` line that matches — so the row
// only means "parseable" if something actually parses it.
function parseYaml(source: string): unknown {
  const runtime = (globalThis as any).Bun;
  if (typeof runtime?.YAML?.parse !== 'function') {
    throw new Error('no YAML parser available in the probe runtime (expected Bun.YAML.parse)');
  }
  return runtime.YAML.parse(source);
}

export default {
  contractVersion: 1,
  sandbox: { snapshot: 'git' },
  probes: [
    {
      name: 'presence-thin-skills',
      description: 'The curated thin-trigger files exist and their frontmatter parses as YAML naming the topic.',
      kind: 'baseline',
      async run(repo: any) {
        for (const topic of topics) {
          const source = await repo.read(`.claude/skills/${topic}/SKILL.md`);
          const frontmatter = source.match(/^---\n([\s\S]*?)\n---/);
          if (!frontmatter) {
            throw new Error(`skill frontmatter is missing: ${topic}`);
          }

          let parsed: unknown;
          try {
            parsed = parseYaml(frontmatter[1]);
          } catch (error) {
            throw new Error(`skill frontmatter is not valid YAML for ${topic}: ${(error as Error).message}`);
          }

          if (typeof parsed !== 'object' || parsed === null || Array.isArray(parsed)) {
            throw new Error(`skill frontmatter for ${topic} is not a YAML mapping`);
          }

          const { name, description } = parsed as Record<string, unknown>;
          if (name !== topic) {
            throw new Error(`skill name mismatch for ${topic}: ${JSON.stringify(name) ?? 'missing'}`);
          }
          if (typeof description !== 'string' || description.trim() === '') {
            throw new Error(`skill description is missing or not a string: ${topic}`);
          }
        }
      },
    },
  ],
};
