export default {
  contractVersion: 1,
  sandbox: { snapshot: 'git' },
  probes: [
    {
      name: 'baseline-readme-tokenization',
      description: 'The README renders the package name, install command, and badge URLs from the scaffold.',
      kind: 'baseline',
      async run(repo: any) {
        const manifest = JSON.parse(await repo.read('package.json'));
        const readme = await repo.read('README.md');
        const name = manifest.name;
        const required = [
          `bun add ${name}`,
          `https://img.shields.io/npm/v/${name}`,
          `https://www.npmjs.com/package/${name}`,
        ];
        for (const token of required) {
          if (!readme.includes(token)) {
            throw new Error(`README is missing the scaffolded token: ${token}`);
          }
        }
      },
    },
  ],
};
