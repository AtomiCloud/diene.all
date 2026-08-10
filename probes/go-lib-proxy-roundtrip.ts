import { defineSmoke } from './lib/definition.ts';
import { expectGreen } from './lib/helpers.ts';

export default defineSmoke({
  sandbox: { snapshot: 'git', preserve: ['.direnv'] },
  baseline: {
    name: 'baseline-go-lib-proxy-roundtrip-green',
    description: 'A clean consumer resolves the real mirror tag through the Go proxy.',
    async run(repo: any) {
      const tag = process.env.GO_LIB_RELEASE_TAG;
      if (!tag) throw new Error('GO_LIB_RELEASE_TAG is required after mirror publication');
      if (!/^v(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)$/.test(tag)) {
        throw new Error('GO_LIB_RELEASE_TAG must match vX.Y.Z');
      }
      await expectGreen(
        repo,
        `nix develop .#ci -c ./scripts/validate/go-proxy-roundtrip.sh ${tag}`,
        'go-lib-proxy-roundtrip',
      );
    },
  },
});
