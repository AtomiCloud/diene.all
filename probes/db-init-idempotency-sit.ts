// COST CLASS: heavy, SERIALIZED (see probes/lib/consumer-sit.ts).
//
// Why heavy is unavoidable: idempotency is a property of the SECOND run against
// real persisted state. A fake store proves the selection logic; only a re-run
// against the real database proves no duplicate rows are created, which is the
// R20 db-init doctrine item this row exists for.
import { runSitJourney } from './lib/consumer-sit.ts';

const JOURNEY = 'TestDBInitIdempotencyJourney';

export default {
  contractVersion: 1,
  sandbox: { snapshot: 'git', preserve: ['.direnv'] },
  probes: [
    {
      name: 'baseline-db-init-idempotency-sit-green',
      description: 'A second seed-if-not-exists run creates no duplicate records.',
      kind: 'baseline',
      async run(repo: any) {
        await runSitJourney(repo, JOURNEY, 'db-init-idempotency-sit');
      },
    },
    {
      name: 'mutation-db-init-idempotency-sit-caught',
      description:
        'Second-run idempotency is defended IN PARALLEL by the loader skip-guard and the ' +
        'seed_records ON CONFLICT; either alone prevents duplicates, so the minimal ' +
        'property-defeating sabotage removes BOTH and the re-run journey then hits a ' +
        'primary-key violation.',
      kind: 'mutation',
      expectedImpact: [],
      async run(repo: any) {
        // TWO coordinated faults, because the property "a second seed run creates no
        // duplicate" is defended IN PARALLEL, not in series:
        //   1. the loader skip-guard `if _, exists := seen[id]; exists { continue }`,
        //      whose `seen` set is seeded from ExistingSeedIDs() — a DB-INFORMED
        //      pre-filter — so InsertSeed is never reached for an already-present id;
        //   2. the seed_records `ON CONFLICT (id) DO NOTHING` backstop, which dedups
        //      if InsertSeed IS reached.
        // Removing EITHER alone leaves the property intact and the gate CORRECTLY green
        // (a one-point sabotage MISSES: guard-only is masked by ON CONFLICT, ON
        // CONFLICT-only is masked by the guard never calling InsertSeed). Both targets
        // are selected by STRUCTURAL PATTERN across the repo, never by sample filename.
        // BOTH patches MUST land — a partially-applied two-point sabotage silently
        // degrades to a one-point one that misses and reads as a gate hole, so a target
        // that fails to match is a HARD ERROR, not a skipped fault.
        const paths = (await repo.glob('**/*.go')).filter(path => !path.endsWith('_test.go')).sort();

        let removedGuard = false;
        for (const path of paths) {
          const source = await repo.read(path);
          const guard = source.match(/\n(\t+)if _, exists := seen\[id\]; exists \{\n\t+continue\n\t+\}\n/);
          if (!guard) {
            continue;
          }
          await repo.write(path, source.replace(guard[0], '\n'));
          removedGuard = true;
          break;
        }
        if (!removedGuard) {
          throw new Error('two-point sabotage incomplete: no structural seed skip-guard found to remove');
        }

        let removedConflict = false;
        for (const path of paths) {
          const source = await repo.read(path);
          const conflict = source.match(
            /(INSERT INTO seed_records \(id, value\)\nVALUES \(\$1, \$2\))\nON CONFLICT \(id\) DO NOTHING/,
          );
          if (!conflict) {
            continue;
          }
          await repo.write(path, source.replace(conflict[0], conflict[1]));
          removedConflict = true;
          break;
        }
        if (!removedConflict) {
          throw new Error(
            'two-point sabotage incomplete: no structural seed_records ON CONFLICT backstop found to remove',
          );
        }

        await runSitJourney(repo, JOURNEY, 'db-init-idempotency-sit', true);
      },
    },
  ],
};
