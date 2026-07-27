export async function expectGreen(repo: any, command: string, label: string): Promise<void> {
  const result = await repo.exec(command, { timeoutMs: 240000 });
  if (result.exitCode !== 0) {
    throw new Error(`${label} failed on the healthy repo: ${result.stderr || result.stdout}`);
  }
}

const PROBE_EVIDENCE_ROOT = '.probe-evidence';

export async function preserveMutationBeforeRestore(
  repo: any,
  evidenceId: string,
  path: string,
  original: string,
): Promise<void> {
  try {
    if (!/^[a-z0-9-]+$/.test(evidenceId)) {
      throw new Error(`invalid probe evidence id: ${evidenceId}`);
    }
    if (path.startsWith('/') || path.split('/').includes('..')) {
      throw new Error(`invalid probe evidence source path: ${path}`);
    }

    const mutated = await repo.read(path);
    const evidencePath = `${PROBE_EVIDENCE_ROOT}/${evidenceId}/${path}`;
    await repo.write(evidencePath, mutated);
    if ((await repo.read(evidencePath)) !== mutated) {
      throw new Error(`probe evidence differs from mutated source: ${evidencePath}`);
    }
  } finally {
    await repo.write(path, original);
  }
}

export async function expectRed(repo: any, command: string, label: string): Promise<void> {
  const result = await repo.exec(command, { timeoutMs: 240000 });
  if (result.exitCode === 0) {
    throw new Error(`${label} stayed green after sabotage`);
  }
}
