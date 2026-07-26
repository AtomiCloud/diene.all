import { runSitJourney } from './lib/consumer-sit.ts';

export default {
  contractVersion: 1,
  sandbox: { snapshot: 'git', preserve: ['.direnv'] },
  probes: [
    {
      name: 'baseline-message-journey-sit-green',
      description: 'An XADD through the compiled binary yields asserted side effects and a consumer-group ack.',
      kind: 'baseline',
      async run(repo: any) {
        await runSitJourney(repo, 'tests/sit/message-journey.sit.test.ts', 'message-journey-sit');
      },
    },
    {
      name: 'mutation-message-journey-sit-caught',
      description: 'A broken consumer handler turns the message journey red.',
      kind: 'mutation',
      async run(repo: any) {
        const source = await repo.read('src/domain/handler.ts');
        const patched = source.replace('payload: message.payload,', "payload: '',");
        if (patched === source) {
          throw new Error('no structural handler persistence field found in src/domain/handler.ts');
        }
        await repo.write('src/domain/handler.ts', patched);
        await runSitJourney(repo, 'tests/sit/message-journey.sit.test.ts', 'message-journey-sit', true);
      },
    },
  ],
};
