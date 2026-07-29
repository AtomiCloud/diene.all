export async function expectGreen(repo: any, command: string, label: string, timeoutMs = 240000): Promise<void> {
  const result = await repo.exec(command, { timeoutMs });
  if (result.exitCode !== 0) {
    throw new Error(`${label} failed on the healthy repo: ${result.stderr || result.stdout}`);
  }
}

export async function expectRed(repo: any, command: string, label: string, timeoutMs = 240000): Promise<void> {
  const result = await repo.exec(command, { timeoutMs });
  if (result.exitCode === 0) {
    throw new Error(`${label} stayed green after sabotage`);
  }
}

// `expectRed` asserts only that the mutation arm exited nonzero, so a mutation that fails to
// parse, fails to load, or crashes renders IDENTICALLY to a real catch in a report that carries
// no stdout. That ambiguity is not theoretical: it is how an empty probe and a working one look
// the same from the outside.
//
// This asserts the mutation failed FOR A NAMED REASON, which makes `caught` unambiguous by
// construction rather than by an external check someone has to remember to repeat. A sabotage
// that dies for the wrong reason reports broken/missed instead of caught.
//
// `reason` must be a string the sabotaged run prints and the HEALTHY run does not — a needle
// present in both proves nothing. Probes should confirm that discrimination directly.
export async function expectRedBecause(
  repo: any,
  command: string,
  label: string,
  reason: string,
  timeoutMs = 240000,
): Promise<void> {
  const result = await repo.exec(command, { timeoutMs });
  const output = `${result.stdout || ''}${result.stderr || ''}`;
  if (result.exitCode === 0) {
    throw new Error(`${label} stayed green after sabotage`);
  }
  if (!output.includes(reason)) {
    throw new Error(
      `${label} failed for the WRONG REASON: expected output to contain ${JSON.stringify(reason)}, got: ${output}`,
    );
  }
}
