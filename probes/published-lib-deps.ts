// Cost: light (<5s) — one manifest read, no install, no shell.
//
// The point of this row is that the app CONSUMES the published Diene libraries
// rather than carrying its own copies of Result, config loading, or problem
// details. A vendored re-implementation would keep every other probe green while
// silently forking the contract the rest of the train depends on.
const runtimeDeps = [
  '@atomicloud/diene.result',
  '@atomicloud/diene.config',
  '@atomicloud/diene.problems',
  '@atomicloud/diene.frontend-utils',
  '@atomicloud/diene.auth-engine',
  '@atomicloud/diene.api-engine',
  '@atomicloud/diene.core-utils',
] as const;

// The e2e train is a devDependency: it drives the suites and never ships.
const devDeps = ['@atomicloud/diene.e2e'] as const;

export default {
  contractVersion: 1,
  sandbox: { snapshot: 'git' },
  probes: [
    {
      name: 'presence-published-lib-deps',
      description: 'The manifest declares every published Diene runtime library plus the e2e train as a devDependency.',
      kind: 'baseline',
      async run(repo: any) {
        const manifest = JSON.parse(await repo.read('package.json'));
        for (const dependency of runtimeDeps) {
          if (manifest.dependencies?.[dependency] === undefined) {
            throw new Error(`package.json does not declare the runtime dependency ${dependency}`);
          }
        }
        for (const dependency of devDeps) {
          if (manifest.devDependencies?.[dependency] === undefined) {
            throw new Error(`package.json does not declare the devDependency ${dependency}`);
          }
        }
      },
    },
  ],
};
