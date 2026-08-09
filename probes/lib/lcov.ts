function normalizeSource(path: string): string {
  const normalized = path.replaceAll('\\\\', '/');
  const sourceIndex = normalized.lastIndexOf('/src/');
  return sourceIndex >= 0 ? normalized.slice(sourceIndex + 1) : normalized;
}

export async function assertScopedLcov(repo: any, file: string, scope: string): Promise<void> {
  const content = await repo.read(file);
  const sources = content
    .split('\n')
    .filter((line: string) => line.startsWith('SF:'))
    .map((line: string) => normalizeSource(line.slice(3)));

  if (sources.length === 0) {
    throw new Error(`${file} contains no source records`);
  }

  const outOfScope = sources.find((source: string) => !source.startsWith(scope));
  if (outOfScope) {
    throw new Error(`${file} contains an out-of-scope source: ${outOfScope}`);
  }

  const expected = [];
  for (const source of (await repo.glob(`${scope}**/*.ts`)).sort()) {
    const body = await repo.read(source);
    if (/^(export )?(async )?(function|class|const|let|var|enum)\b|^\s*(const|let|var)\b/m.test(body)) {
      expected.push(source);
    }
  }
  const covered = new Set(sources);
  const missing = expected.find((source: string) => !covered.has(source));
  if (missing) {
    throw new Error(`${file} omits source from its ledger: ${missing}`);
  }

  const lineValues = content
    .split('\n')
    .filter((line: string) => line.startsWith('LF:') || line.startsWith('LH:'))
    .reduce(
      (totals: { found: number; hit: number }, line: string) => {
        const value = Number(line.slice(3));
        if (line.startsWith('LF:')) totals.found += value;
        else totals.hit += value;
        return totals;
      },
      { found: 0, hit: 0 },
    );

  if (lineValues.found === 0 || lineValues.hit !== lineValues.found) {
    throw new Error(`${file} is not at 100% line coverage: ${lineValues.hit}/${lineValues.found}`);
  }
}
