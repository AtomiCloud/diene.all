import { expectBunGreen, expectBunRed } from './lib/bun-command.ts';

// Cost: light (<30s).
const command =
  "nix develop .#ci -c bash -lc './scripts/ci/setup.sh && bun test --config=bunfig.unit.toml tests/unit/problem-contract.test.ts'";

export default {
  contractVersion: 1,
  sandbox: { snapshot: 'git', preserve: ['.direnv'] },
  probes: [
    {
      name: 'baseline-problem-contract-green',
      description:
        'Every emitted error is an RFC 9457 envelope whose type URI addresses this service error portal, api-engine problems included.',
      kind: 'baseline',
      async run(repo: any) {
        await expectBunGreen(repo, command, 'problem-contract');
      },
    },
    {
      name: 'mutation-problem-contract-caught',
      description: 'Dropping the api-engine problem registration turns the contract suite red.',
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
        // Without registerApiProblems the transport failures become a SECOND,
        // unaddressable error surface: the type URIs no longer resolve to any
        // published error-info document.
        const path = 'src/adapters/problem-reporter/registry.ts';
        const source = await repo.read(path);
        await repo.write(
          path,
          source
            .replace(
              /return registerApiProblems\(registry\)\.map\(api => \(\{ registry, api \}\)\);/,
              'return Ok({ registry, api: {} as ApiProblems });',
            )
            .replace(
              /^import \{ createGenericProblemRegistry/m,
              "import { Ok } from '@atomicloud/diene.result';\nimport { createGenericProblemRegistry",
            ),
        );
        await expectBunRed(repo, command, 'problem-contract');
      },
    },
  ],
};
