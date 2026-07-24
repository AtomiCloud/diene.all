import { expectGreen, expectRed } from './lib/helpers.ts';

// Gate: `scripts/ci/test.sh unit coverage` enforces a 100% line-coverage ledger
// over `lib/src`. Sabotage adds a public, uncovered library member (exported
// from the barrel) and proves the ledger drops below 100% and fails.
async function findBarrel(repo: any): Promise<string> {
  const candidates = (await repo.glob('packages/*/lib/*.dart')).sort();
  for (const candidate of candidates) {
    if ((await repo.read(candidate)).includes("export 'src/")) {
      return candidate;
    }
  }
  throw new Error('unit-coverage-ledger: no library barrel exporting src/ found');
}

export default {
  contractVersion: 1,
  sandbox: { snapshot: 'git', preserve: ['.direnv'] },
  setup: {
    post: [
      'nix develop .#ci --no-write-lock-file -c dart pub get --offline || nix develop .#ci --no-write-lock-file -c dart pub get',
    ],
  },
  probes: [
    {
      name: 'baseline-unit-coverage-ledger-green',
      description: 'the unit coverage ledger holds at 100% on the pristine template',
      kind: 'baseline',
      async run(repo: any) {
        await expectGreen(
          repo,
          'nix develop .#ci --no-write-lock-file -c ./scripts/ci/test.sh unit coverage',
          'unit-coverage-ledger',
        );
      },
    },
    {
      name: 'mutation-unit-coverage-ledger-caught',
      description: 'the unit coverage ledger fails when an uncovered public member is added',
      kind: 'mutation',
      expectedImpact: [],
      async run(repo: any) {
        const barrel = await findBarrel(repo);
        const memberDir = barrel.replace(/\/lib\/[^/]+$/, '');
        await repo.write(`${memberDir}/lib/src/probe_uncovered.dart`, 'int probeUncovered() {\n  return 1;\n}\n');
        await repo.write(barrel, `${await repo.read(barrel)}\nexport 'src/probe_uncovered.dart';\n`);
        await expectRed(
          repo,
          'nix develop .#ci --no-write-lock-file -c ./scripts/ci/test.sh unit coverage',
          'unit-coverage-ledger',
        );
      },
    },
  ],
};
