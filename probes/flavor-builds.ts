import { createHash } from 'node:crypto';

const flavors = ['lapras', 'pichu', 'pikachu', 'raichu'] as const;
const outerTimeoutMs = 1_800_000;
const aggregateBudgetMs = 1_680_000;
const killAfterSeconds = 15;
const outputTailChars = 2_048;

type FlavorEvidence = {
  flavor: (typeof flavors)[number];
  command: string;
  elapsedMs: number;
  exitCode: number;
  timedOut: boolean;
  signal: string | null;
  stdoutBytes: number;
  stdoutSha256: string;
  stdoutTail: string;
  stderrBytes: number;
  stderrSha256: string;
  stderrTail: string;
};

function tail(value: string): string {
  return value.slice(-outputTailChars);
}

function sha256(value: string): string {
  return createHash('sha256').update(value).digest('hex');
}

function signalFromExitCode(exitCode: number): string | null {
  return (
    (
      {
        130: 'INT',
        137: 'KILL',
        143: 'TERM',
      } as Record<number, string>
    )[exitCode] ?? null
  );
}

function resultEvidence(
  flavor: (typeof flavors)[number],
  command: string,
  elapsedMs: number,
  result: { exitCode: number; stdout: string; stderr: string },
): FlavorEvidence {
  const timeoutSignals = Array.from(
    result.stderr.matchAll(/timeout: sending signal ([A-Z0-9]+) to command/g),
    match => match[1],
  );
  return {
    flavor,
    command,
    elapsedMs,
    exitCode: result.exitCode,
    timedOut: timeoutSignals.length > 0,
    signal: timeoutSignals.at(-1) ?? signalFromExitCode(result.exitCode),
    stdoutBytes: Buffer.byteLength(result.stdout),
    stdoutSha256: sha256(result.stdout),
    stdoutTail: tail(result.stdout),
    stderrBytes: Buffer.byteLength(result.stderr),
    stderrSha256: sha256(result.stderr),
    stderrTail: tail(result.stderr),
  };
}

function formatEvidence(evidence: FlavorEvidence[]): string {
  return `FLAVOR_BUILD_EVIDENCE ${JSON.stringify(evidence)}`;
}

export default {
  contractVersion: 1,
  sandbox: { snapshot: 'git', preserve: ['.direnv'] },
  probes: [
    {
      name: 'baseline-flavor-builds-green',
      description: 'Lapras, pichu, pikachu, and raichu build with their baked landscape define.',
      kind: 'baseline',
      timeoutMs: outerTimeoutMs,
      async run(repo: any) {
        const evidence: FlavorEvidence[] = [];
        const aggregateStartedAt = Date.now();

        for (const flavor of flavors) {
          const remainingMs = aggregateBudgetMs - (Date.now() - aggregateStartedAt);
          if (remainingMs <= 0) {
            const message = formatEvidence(evidence);
            console.log(message);
            throw new Error(
              `flavor-builds exhausted its ${aggregateBudgetMs}ms aggregate budget before ${flavor}: ${message}`,
            );
          }

          const remainingSeconds = Math.max(1, Math.floor(remainingMs / 1_000));
          const command =
            `mode="\${BUILD_MODE:-debug}"; ` +
            `timeout --verbose --signal=TERM --kill-after=${killAfterSeconds}s ${remainingSeconds}s ` +
            `nix develop .#default -c flutter build apk --"$mode" --flavor ${flavor} ` +
            `--dart-define=FLUTTER_BASE_LANDSCAPE=${flavor}`;
          const startedAt = Date.now();
          const result = await repo.exec(command);
          evidence.push(resultEvidence(flavor, command, Date.now() - startedAt, result));

          if (result.exitCode !== 0) {
            const message = formatEvidence(evidence);
            console.log(message);
            throw new Error(`flavor-builds failed for ${flavor}: ${message}`);
          }
        }

        console.log(formatEvidence(evidence));
      },
    },
  ],
};
