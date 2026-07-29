import { expectBunGreen, expectBunRed } from './lib/bun-command.ts';

// Cost: light (<30s) — the well-known documents are built by pure functions, so the
// SCHEMA is provable without a server. (The served route is separately proven by
// the Bruno collection and the well-known browser slice.)
const command =
  "nix develop .#ci -c bash -lc './scripts/ci/setup.sh && bun test --config=bunfig.unit.toml tests/unit/deeplink-well-known.test.ts'";

export default {
  contractVersion: 1,
  sandbox: { snapshot: 'git', preserve: ['.direnv'] },
  probes: [
    {
      name: 'baseline-well-known-schema-green',
      description:
        'The AASA and assetlinks documents match the shapes Apple and Google actually accept, including the handle-all-urls relation.',
      kind: 'baseline',
      async run(repo: any) {
        await expectBunGreen(repo, command, 'well-known-schema');
      },
    },
    {
      name: 'mutation-well-known-schema-caught',
      description: 'A wrong assetlinks relation turns the well-known schema suite red.',
      kind: 'mutation',
      // MEASURED COLLATERAL (family: shared source read by the unit suite). This
      // sabotage edits a real src/ module, and bunfig.unit.toml roots the suite at
      // tests/unit where 16 of 20 files import ../../src/**, so the whole unit run
      // reddens. On the 6f5907a matrix this row broke with control_failed naming
      // diene/bun-base#bun-unit-tests, control output "task: [unit:default] bun test"
      // - the control RAN and FAILED, so the blame was correct, and the empty array
      // here was a positive assertion of no collateral that got believed.
      expectedImpact: ['bun-unit-tests'],
      async run(repo: any) {
        // `get_login_creds` is a real relation, so the document stays valid JSON and
        // valid assetlinks — it just no longer authorises app links, and Android
        // silently opens the browser instead of the app.
        const path = 'src/lib/deeplink/well-known.ts';
        const source = await repo.read(path);
        await repo.write(
          path,
          source.replace(
            "relation: ['delegate_permission/common.handle_all_urls'],",
            "relation: ['delegate_permission/common.get_login_creds'],",
          ),
        );
        await expectBunRed(repo, command, 'well-known-schema');
      },
    },
  ],
};
