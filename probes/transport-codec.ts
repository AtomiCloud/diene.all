import { expectBunGreen, expectBunRed } from './lib/bun-command.ts';

// Cost: light (<30s).
const command =
  "nix develop .#ci -c bash -lc './scripts/ci/setup.sh && bun test --config=bunfig.unit.toml tests/unit/domain-codec.test.ts'";

export default {
  contractVersion: 1,
  sandbox: { snapshot: 'git', preserve: ['.direnv'] },
  probes: [
    {
      name: 'baseline-transport-codec-green',
      description:
        'The C0 wire codec round-trips the domain type: standardized strings on the wire, Temporal values in the domain, both directions lossless.',
      kind: 'baseline',
      async run(repo: any) {
        await expectBunGreen(repo, command, 'transport-codec');
      },
    },
    {
      name: 'mutation-transport-codec-caught',
      description:
        'Serialising an instant with the default string conversion instead of the wire format turns the round trip red.',
      kind: 'mutation',
      expectedImpact: [],
      async run(repo: any) {
        // `String(instant)` produces a plausible-looking timestamp that still
        // typechecks and still parses in some readers — and disagrees with the
        // format every other service on the wire has agreed to.
        const path = 'src/lib/domain/codec.ts';
        const source = await repo.read(path);
        await repo.write(path, source.replace('formatWireDateTime(reminder.remindAt)', 'String(reminder.remindAt)'));
        await expectBunRed(repo, command, 'transport-codec');
      },
    },
  ],
};
