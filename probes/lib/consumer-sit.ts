// SIT journey harness: each row drives ONE journey file through the compiled
// binary against the full local dependency stack. Host ports come from
// config/dev.yaml, so stacks cannot coexist — the whole up→journey→down
// sequence serializes on a host-level flock (PROBES §5 addendum: declared
// serialization where per-invocation uniqueness is genuinely impractical).
const LOCK = '/tmp/diene-bunconsumer-sit.lock';

export function sitJourneyCommand(journeyFile: string): string {
  const inner =
    './scripts/local/setup.sh && ./scripts/local/compile.sh && ./scripts/local/up.sh && ' +
    `rc=0; SIT_DRIVER=binary CLI_BIN=dist/bin/bun-consumer bun test --config=bunfig.sit.toml ${journeyFile} || rc=$?; ` +
    './scripts/local/down.sh || true; exit $rc';
  return `nix develop .#ci -c bash -lc 'flock ${LOCK} bash -c ${JSON.stringify(inner)}'`;
}

export async function runSitJourney(repo: any, journeyFile: string, label: string, expectFail = false): Promise<void> {
  const result = await repo.exec(sitJourneyCommand(journeyFile), { timeoutMs: 1800000 });
  if (!expectFail && result.exitCode !== 0) {
    throw new Error(`${label} failed on the healthy repo: ${result.stderr || result.stdout}`);
  }
  if (expectFail && result.exitCode === 0) {
    throw new Error(`${label} stayed green after sabotage`);
  }
}
