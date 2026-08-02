import { defineSmoke } from './lib/definition.ts';
import { expectGreen } from './lib/helpers.ts';

export default defineSmoke({
  sandbox: { snapshot: 'git', preserve: ['.direnv'] },
  baseline: {
    name: 'baseline-wrapper-publish-oci-green',
    description: 'The default OCI package/ref dry-run succeeds without publishing externally.',
    async run(repo: any) {
      await expectGreen(
        repo,
        'nix develop .#cd -c ./scripts/validate/helm-wrapper.sh publish-oci',
        'wrapper-publish-oci',
      );
    },
  },
});
