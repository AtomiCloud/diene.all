import { expectBunGreen, expectBunRed } from './lib/bun-command.ts';

// Cost: light (<30s) — the allowlist derivation is pure.
const command =
  "nix develop .#ci -c bash -lc './scripts/ci/setup.sh && bun test --config=bunfig.unit.toml tests/unit/allowlist.test.ts'";

export default {
  contractVersion: 1,
  sandbox: { snapshot: 'git', preserve: ['.direnv'] },
  probes: [
    {
      name: 'baseline-picker-allowlist-green',
      description:
        'The baked suffix allowlist is the picker security boundary (there is no doc signing): it accepts the configured hosts and rejects everything else.',
      kind: 'baseline',
      async run(repo: any) {
        await expectBunGreen(repo, command, 'picker-allowlist');
      },
    },
    {
      name: 'mutation-picker-allowlist-caught',
      description: 'A permissive empty suffix turns the allowlist reject table red.',
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
        // An empty suffix is a suffix of EVERY host, so the allowlist keeps its shape
        // and stops excluding anything. Doc B could then be fetched from any origin
        // an attacker controls, and the picker would trust its landscape list.
        const path = 'src/lib/allowlist/index.ts';
        const source = await repo.read(path);
        await repo.write(
          path,
          source.replace(
            "suffixes: picker.allowedSuffixes.filter(suffix => suffix.trim() !== ''),",
            "suffixes: [...picker.allowedSuffixes, ''],",
          ),
        );
        await expectBunRed(repo, command, 'picker-allowlist');
      },
    },
  ],
};
