import { expectGreen, expectRed } from './lib/helpers.ts';

// Gate: `scripts/validate/publish-version.sh` refuses to publish unless the
// member pubspec version and the VERSION ledger agree with the release tag.
// Sabotage drifts the member pubspec version away from VERSION and proves the
// guard rejects the mismatch.
const GUARD =
  "nix develop .#ci --no-write-lock-file -c bash -lc 'GITHUB_REF_NAME=v$(cat VERSION) ./scripts/validate/publish-version.sh'";

export default {
  contractVersion: 1,
  sandbox: { snapshot: 'git', preserve: ['.direnv'] },
  probes: [
    {
      name: 'baseline-publish-version-guard-green',
      description: 'the version guard passes when pubspec, VERSION, and tag agree',
      kind: 'baseline',
      async run(repo: any) {
        await expectGreen(repo, GUARD, 'publish-version-guard');
      },
    },
    {
      name: 'mutation-publish-version-guard-caught',
      description: 'the version guard fails once the member pubspec version drifts',
      kind: 'mutation',
      expectedImpact: [],
      async run(repo: any) {
        const version = (await repo.read('VERSION')).trim();
        await repo.patch('packages/diene_dart_lib/pubspec.yaml', {
          find: `version: ${version}`,
          replace: `version: ${version}-probe-drift`,
        });
        await expectRed(repo, GUARD, 'publish-version-guard');
      },
    },
  ],
};
