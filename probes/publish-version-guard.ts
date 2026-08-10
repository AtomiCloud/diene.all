import { expectGreen, expectRed } from './lib/helpers.ts';

export default {
  contractVersion: 1,
  sandbox: { snapshot: 'git', preserve: ['.direnv'] },
  probes: [
    {
      name: 'baseline-publish-version-guard-green',
      description: 'The publish version guard passes when the manifest matches the tag.',
      kind: 'baseline',
      async run(repo: any) {
        const version = JSON.parse(await repo.read('package.json')).version;
        await expectGreen(
          repo,
          `nix develop .#ci -c bash -lc 'GITHUB_REF_NAME=v${version} ./scripts/ci/verify-version.sh'`,
          'publish-version-guard',
        );
      },
    },
    {
      name: 'mutation-publish-version-guard-caught',
      description: 'A manifest version that drifts from the tag must exit 1 before publication.',
      kind: 'mutation',
      expectedImpact: [],
      async run(repo: any) {
        const manifest = JSON.parse(await repo.read('package.json'));
        const tag = manifest.version;
        manifest.version = `${manifest.version}-probe-drift`;
        await repo.write('package.json', `${JSON.stringify(manifest, null, 2)}\n`);
        await expectRed(
          repo,
          `nix develop .#ci -c bash -lc 'GITHUB_REF_NAME=v${tag} ./scripts/ci/verify-version.sh'`,
          'publish-version-guard',
        );
      },
    },
  ],
};
