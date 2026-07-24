import { defineSmoke } from './lib/definition.ts';
import { expectBunGreen } from './lib/bun-command.ts';

export default defineSmoke({
  sandbox: { snapshot: 'git', preserve: ['.direnv'] },
  baseline: {
    name: 'baseline-bun-lib-dual-build-green',
    description: 'The library build emits ESM, CommonJS, and both declaration kinds.',
    async run(repo: any) {
      await expectBunGreen(
        repo,
        "nix develop .#ci -c bash -lc './scripts/ci/setup.sh && ./scripts/local/build.sh && test -f dist/index.js && test -f dist/index.cjs && test -f dist/index.d.ts && test -f dist/index.d.cts && cmp -s dist/index.d.ts dist/index.d.cts'",
        'bun-lib-dual-build',
      );
    },
  },
});
