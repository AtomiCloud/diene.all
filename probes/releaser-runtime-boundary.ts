// Static installer/runtime pin gate (pure read/grep, no execution, cannot
// publish). Guards against regression to runner-incidental yarn/pnpm selection:
// the release script must pin the npm installer (`-i npm`) and the releaser env
// group must carry `nodejs` so node/npm are deterministically present.
const RELEASE_LINE = /releaser release -c atomi_release\.yaml -i npm/;

async function assertRuntimePinned(repo: any): Promise<void> {
  const release = await repo.read('scripts/ci/release.sh');
  if (!RELEASE_LINE.test(release)) {
    throw new Error('scripts/ci/release.sh does not pin the npm installer (-i npm)');
  }
  const env = await repo.read('nix/env.nix');
  const group = env.match(/releaser = \[([^\]]*)\]/);
  if (!group || !/\bnodejs\b/.test(group[1])) {
    throw new Error('nix/env.nix releaser group does not list nodejs');
  }
}

export default {
  contractVersion: 1,
  sandbox: { snapshot: 'git' },
  probes: [
    {
      name: 'baseline-releaser-runtime-boundary-green',
      description:
        'scripts/ci/release.sh pins the npm installer (-i npm) and the releaser env group lists nodejs, so the release runtime is deterministic rather than runner-incidental.',
      kind: 'baseline',
      async run(repo: any) {
        await assertRuntimePinned(repo);
      },
    },
    {
      name: 'mutation-releaser-runtime-boundary-caught',
      description:
        'Removing the -i npm installer pin must turn the runtime-boundary gate red, preventing silent return to runner-incidental yarn/pnpm selection.',
      kind: 'mutation',
      expectedImpact: [],
      async run(repo: any) {
        await repo.patch('scripts/ci/release.sh', {
          find: 'releaser release -c atomi_release.yaml -i npm',
          replace: 'releaser release -c atomi_release.yaml',
        });
        let caught = false;
        try {
          await assertRuntimePinned(repo);
        } catch {
          caught = true;
        }
        if (!caught) {
          throw new Error('runtime-boundary gate stayed green after removing the -i npm pin');
        }
      },
    },
  ],
};
