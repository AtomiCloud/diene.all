// COST CLASS: light (<30s) — a yq/awk comparison over two files, no compile.
//
// The mechanism is `scripts/validate/constants-sync.sh`, registered as a
// chain-side pre-commit hook: the typed constants in `lib/appconfig/constants.go`
// must mirror every keyed-adapter block key in `config/settings.yaml`.
import { expectRed } from './lib/helpers.ts';

const CHECK = "nix develop .#ci -c bash -lc './scripts/validate/constants-sync.sh'";

export default {
  contractVersion: 1,
  sandbox: { snapshot: 'git', preserve: ['.direnv'] },
  probes: [
    {
      name: 'baseline-constants-sync-green',
      description: 'Typed constants mirror every keyed-adapter configuration key, with the counts printed.',
      kind: 'baseline',
      async run(repo: any) {
        const result = await repo.exec(CHECK, { timeoutMs: 240000 });
        const transcript = `${result.stdout ?? ''}\n${result.stderr ?? ''}`;
        if (result.exitCode !== 0) {
          throw new Error(`constants-sync-lint failed on the healthy repo:\n${transcript}`);
        }
        // Assert on the printed VALUES and refuse a ZERO match. A comparison of an
        // empty key set against an empty constant set is trivially equal, so a
        // gate that only reported "0 unmatched" would pass on a tree whose config
        // or constants file had been emptied. The script itself now refuses zero;
        // this row asserts that refusal is real rather than trusting it.
        const counts = transcript.match(/(\d+) config keys, (\d+) constants, (\d+) unmatched/);
        if (!counts) {
          throw new Error(
            `constants-sync-lint exited 0 without printing its counts — refusing a silent pass:\n${transcript}`,
          );
        }
        const [, configKeys, constants, unmatched] = counts;
        if (Number(configKeys) === 0 || Number(constants) === 0) {
          throw new Error(
            `constants-sync-lint passed on an EMPTY match (${configKeys} config keys, ${constants} constants) — a zero-versus-zero comparison is vacuous`,
          );
        }
        if (Number(unmatched) !== 0) {
          throw new Error(`constants-sync-lint reported ${unmatched} unmatched keys on the healthy repo`);
        }
      },
    },
    {
      name: 'mutation-constants-sync-caught',
      description: 'A keyed-adapter config key added without its typed constant turns the hook red.',
      kind: 'mutation',
      expectedImpact: [],
      async run(repo: any) {
        // ONE fault: add a keyed-adapter instance to configuration and NOT its
        // typed constant. Structural target — the `kv:` block is selected by the
        // keyed-adapter shape the gate itself scans (postgres/cache/kv/storage),
        // not by a sample filename, and the added key is a full valid instance so
        // the only thing wrong is the missing constant.
        const path = 'config/settings.yaml';
        const source = await repo.read(path);
        const block = source.match(/^kv:\n(\s+)([A-Z][A-Z0-9_]*):\n/m);
        if (!block) {
          throw new Error(`no structural keyed kv block found in ${path}`);
        }
        const indent = block[1];
        const added = [
          'kv:',
          `${indent}PROBESYNC:`,
          `${indent}${indent}host: kv`,
          `${indent}${indent}port: 6379`,
          `${indent}${indent}password: ''`,
          `${indent}${indent}db: 0`,
          `${indent}${indent}tls: false`,
          '',
        ].join('\n');
        await repo.write(path, source.replace(/^kv:\n/m, added));
        await expectRed(repo, CHECK, 'constants-sync-lint');
      },
    },
  ],
};
