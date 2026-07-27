import { runSitJourney, sitScript } from './lib/consumer-sit.ts';

const JOURNEY = 'tests/sit/otel-export.sit.test.ts';
const EXPECTED_FAILURE = 'probe-otel-trace-export-blocked';

function mutationSitCommand(): string {
  const assertion = `const sit = await import(process.cwd() + '/tests/sit/driver.ts');
const driver = sit.consumerDriver();
const initialized = await sit.initialize(driver);
if (initialized.code !== 0) throw new Error(initialized.err || initialized.out || 'db-init failed');
const id = crypto.randomUUID();
const consumerName = 'otel-probe-' + id;
const stream = 'sit.otel.probe.' + id;
const worker = await driver.run(['worker', '--once'], {
  ATOMI_HEALTH__HEARTBEAT_FILE: 'dist/run/otel-probe-' + id + '.json',
  ATOMI_OTEL__TRACES__EXPORTER__OTLP__ENDPOINT: 'https://localhost:4318',
  ATOMI_TRANSPORT__CONSUMER_GROUP: 'sit-probe-' + id,
  ATOMI_TRANSPORT__CONSUMER_NAME: consumerName,
  ATOMI_TRANSPORT__STREAM: stream,
});
if (worker.code !== 0) throw new Error(worker.err || worker.out || 'worker failed');
let traceRows = 0;
try {
  await sit.waitFor(async () => {
    const query = encodeURIComponent(
      "SELECT count() FROM otel.otel_traces WHERE SpanAttributes['messaging.destination.name'] = '" + stream + "'",
    );
    const response = await fetch(sit.devConfig.clickhouse.endpoint + '/?query=' + query);
    if (!response.ok) throw new Error('ClickHouse query failed with status ' + response.status);
    traceRows = Number(await response.text());
    return traceRows > 0;
  }, 45_000);
} catch (error) {
  if (!(error instanceof Error) || !error.message.startsWith('condition was not met within')) throw error;
}
if (traceRows > 0) process.exit(0);
console.error('${EXPECTED_FAILURE}');
process.exit(1);
`;
  const encodedAssertion = Buffer.from(assertion, 'utf8').toString('base64');
  const healthyInvocation = `SIT_DRIVER=binary CLI_BIN=dist/bin/bun-consumer bun test --config=bunfig.sit.toml ${JOURNEY}`;
  const mutationInvocation = `probe_file="$(mktemp)"
echo ${encodedAssertion} | base64 -d >"$probe_file"
set +e
SIT_DRIVER=binary CLI_BIN=dist/bin/bun-consumer bun "$probe_file"
probe_rc=$?
set -e
rm -f "$probe_file"
exit "$probe_rc"`;
  const source = sitScript(JOURNEY);
  const patched = source.replace(healthyInvocation, mutationInvocation);
  if (patched === source) {
    throw new Error('no structural OTel SIT assertion invocation found');
  }
  const encodedScript = Buffer.from(patched, 'utf8').toString('base64');
  return `nix develop .#ci -c bash -lc 'f="$(mktemp)"; echo ${encodedScript} | base64 -d >"$f"; bash "$f" </dev/null; r=$?; rm -f "$f"; exit $r'`;
}

export default {
  contractVersion: 1,
  sandbox: { snapshot: 'git', preserve: ['.direnv'] },
  probes: [
    {
      name: 'baseline-otel-export-sit-green',
      description: 'Logs, traces, and metrics traverse the local alloy → ClickHouse/VictoriaMetrics path in SIT.',
      kind: 'baseline',
      async run(repo: any) {
        await runSitJourney(repo, JOURNEY, 'otel-export-sit');
      },
    },
    {
      name: 'mutation-otel-export-sit-caught',
      description:
        'Broken exporter configuration turns the otel-export journey red while the app itself stays healthy.',
      kind: 'mutation',
      async run(repo: any) {
        const result = await repo.exec(mutationSitCommand(), { timeoutMs: 1800000 });
        const output = `${result.stdout}\n${result.stderr}`;
        if (result.exitCode === 0) {
          throw new Error('otel-export-sit stayed green after the trace exporter sabotage');
        }
        if (!output.includes(EXPECTED_FAILURE)) {
          throw new Error(`otel-export-sit failed before the trace assertion: ${result.stderr || result.stdout}`);
        }
      },
    },
  ],
};
