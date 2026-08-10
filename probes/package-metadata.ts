import { expectGreen, expectRed } from './lib/helpers.ts';

const METADATA = 'nix develop .#ci -c ./scripts/validate/package-metadata.sh';

export default {
  contractVersion: 1,
  sandbox: { snapshot: 'git', preserve: ['.direnv'] },
  probes: [
    {
      name: 'baseline-package-metadata-green',
      description: 'The manifest license agrees with the root LICENSE.',
      kind: 'baseline',
      async run(repo: any) {
        await expectGreen(repo, METADATA, 'package-metadata');
      },
    },
    {
      name: 'mutation-package-metadata-caught',
      description: 'A manifest license that disagrees with the root LICENSE must redden the metadata gate.',
      kind: 'mutation',
      expectedImpact: [],
      async run(repo: any) {
        const manifest = JSON.parse(await repo.read('package.json'));
        manifest.license = 'Apache-2.0';
        await repo.write('package.json', `${JSON.stringify(manifest, null, 2)}\n`);
        await expectRed(repo, METADATA, 'package-metadata');
      },
    },
  ],
};
