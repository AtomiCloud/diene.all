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
        'Replacing the seed-if-not-exists selection with an unconditional insert turns the re-run journey red.',
      kind: 'mutation',
      expectedImpact: [],
      async run(repo: any) {
        // ONE fault: remove the "already present" short-circuit so every seed record
        // is inserted UNCONDITIONALLY on every run. The target is found by PATTERN —
        // the existence-set membership guard inside whichever `lib/` package owns the
        // seed loader — selected by glob, never by sample filename. This is the one
        // fault that makes a second run duplicate; deleting the seed file would not
        // qualify.
        const paths = (await repo.glob('lib/**/*.go')).filter(path => !path.endsWith('_test.go')).sort();
        for (const path of paths) {
          const source = await repo.read(path);
          const guard = source.match(/\n(\t+)if _, exists := seen\[id\]; exists \{\n\t+continue\n\t+\}\n/);
          if (!guard) {
            continue;
          }
          await repo.write(path, source.replace(guard[0], '\n'));
          await runSitJourney(repo, JOURNEY, 'db-init-idempotency-sit', true);
          return;
        }
        throw new Error('no structural seed-if-not-exists selection found under lib/');
      },
    },
  ],
};
