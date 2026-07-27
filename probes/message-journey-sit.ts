// COST CLASS: heavy, SERIALIZED (see probes/lib/consumer-sit.ts).
//
// Why heavy is unavoidable: the mechanism is the full produce→consume→side-effect
// path — XADD into the redis-streams transport, the compiled worker consuming and
// acking it, and the asserted side effects (the encrypted object in storage and the
// processed-message row in postgres). No lighter proxy reaches all three stores
// through the real transport.
import { runSitJourney } from './lib/consumer-sit.ts';

const JOURNEY = 'TestMessageJourney';

export default {
  contractVersion: 1,
  sandbox: { snapshot: 'git', preserve: ['.direnv'] },
  probes: [
    {
      name: 'baseline-message-journey-sit-green',
      description: 'An XADD through the compiled worker yields the asserted side effects and a consumer-group ack.',
      kind: 'baseline',
      async run(repo: any) {
        await runSitJourney(repo, JOURNEY, 'message-journey-sit');
      },
    },
    {
      name: 'mutation-message-journey-sit-caught',
      description: 'A broken consumer handler turns the message journey red.',
      kind: 'mutation',
      expectedImpact: [],
      async run(repo: any) {
        // ONE fault: the handler persists a BLANK payload instead of the consumed
        // one, so the pipeline still runs end to end and still acks — only the
        // asserted side effect is wrong. That is the regression this row must catch;
        // throwing from the handler would instead be caught by any liveness check.
        // The target is found by PATTERN — the record field that carries the consumed
        // payload — inside whichever `lib/` package owns the handler, by glob.
        const paths = (await repo.glob('lib/**/*.go')).filter(path => !path.endsWith('_test.go')).sort();
        for (const path of paths) {
          const source = await repo.read(path);
          const field = source.match(/Payload:\s*message\.Payload,/);
          if (!field) {
            continue;
          }
          await repo.write(path, source.replace(field[0], 'Payload: "",'));
          await runSitJourney(repo, JOURNEY, 'message-journey-sit', true);
          return;
        }
        throw new Error('no structural consumed-payload persistence field found under lib/');
      },
    },
  ],
};
