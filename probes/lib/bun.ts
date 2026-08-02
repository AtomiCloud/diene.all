// Node-owned: the shared helpers stay language-agnostic, so Bun-shaped knowledge lives here.

export type LcovRecord = {
  file: string;
  linesFound: number;
  linesHit: number;
  functionsFound: number;
  functionsHit: number;
};

export type CoverageThreshold = {
  // The strictest declared component; a sabotage sized against it clears every other one too.
  effective: number;
  declared: Record<string, number>;
};

type MutationResult = {
  path: string;
};

type Replacement = {
  find: RegExp;
  replace: string;
};

// None of these match an already-negated form, so applying one always changes the verdict.
export const ASSERTION_FLIPS: Replacement[] = [
  { find: /should\(([^)]*)\)\.equal\(/, replace: 'should($1).not.equal(' },
  { find: /should\(([^)]*)\)\.eql\(/, replace: 'should($1).not.eql(' },
  { find: /should\(([^)]*)\)\.be\.null\(\)/, replace: 'should($1).not.be.null()' },
  { find: /should\(([^)]*)\)\.throw\(/, replace: 'should($1).not.throw(' },
  { find: /expect\(([^)]*)\)\.toBe\(/, replace: 'expect($1).not.toBe(' },
  { find: /expect\(([^)]*)\)\.toEqual\(/, replace: 'expect($1).not.toEqual(' },
];

function numberFrom(raw: string, field: string): number {
  const value = Number(raw);
  if (!Number.isFinite(value)) {
    throw new Error(`unreadable lcov ${field} value: ${raw}`);
  }
  return value;
}

// A missing counter is not a zero counter: defaulting it lets an unmeasured file read as an answer.
function requireField(value: number | undefined, field: string, file: string): number {
  if (value === undefined) {
    throw new Error(`lcov record for ${file} declares no ${field}`);
  }
  return value;
}

export function parseLcov(source: string): LcovRecord[] {
  const records: LcovRecord[] = [];
  let file: string | undefined;
  let linesFound: number | undefined;
  let linesHit: number | undefined;
  let functionsFound: number | undefined;
  let functionsHit: number | undefined;

  for (const line of source.split('\n')) {
    const trimmed = line.trim();
    if (trimmed.startsWith('SF:')) {
      file = trimmed.slice(3);
      linesFound = undefined;
      linesHit = undefined;
      functionsFound = undefined;
      functionsHit = undefined;
      continue;
    }
    if (trimmed.startsWith('LF:')) linesFound = numberFrom(trimmed.slice(3), 'LF');
    if (trimmed.startsWith('LH:')) linesHit = numberFrom(trimmed.slice(3), 'LH');
    if (trimmed.startsWith('FNF:')) functionsFound = numberFrom(trimmed.slice(4), 'FNF');
    if (trimmed.startsWith('FNH:')) functionsHit = numberFrom(trimmed.slice(4), 'FNH');
    if (trimmed !== 'end_of_record') continue;

    if (file === undefined) {
      throw new Error('lcov end_of_record without a preceding SF: record');
    }
    records.push({
      file,
      linesFound: requireField(linesFound, 'LF', file),
      linesHit: requireField(linesHit, 'LH', file),
      functionsFound: requireField(functionsFound, 'FNF', file),
      functionsHit: requireField(functionsHit, 'FNH', file),
    });
    file = undefined;
  }

  if (records.length === 0) {
    throw new Error('the coverage ledger is empty — a sweep over zero files is not a coverage result');
  }
  return records;
}

export async function readLcov(repo: any, path: string): Promise<LcovRecord[]> {
  let source: string;
  try {
    source = await repo.read(path);
  } catch (error) {
    throw new Error(`could not read the coverage ledger at ${path}: ${(error as Error).message}`);
  }
  return parseLcov(source);
}

export function lineRate(records: readonly LcovRecord[]): number {
  const found = records.reduce((total, record) => total + record.linesFound, 0);
  if (found === 0) {
    throw new Error('the coverage ledger instruments zero lines');
  }
  return records.reduce((total, record) => total + record.linesHit, 0) / found;
}

export function functionRate(records: readonly LcovRecord[]): number {
  const found = records.reduce((total, record) => total + record.functionsFound, 0);
  if (found === 0) {
    return 1;
  }
  return records.reduce((total, record) => total + record.functionsHit, 0) / found;
}

// The absent-file half is load-bearing: a file missing from the report leaves a vacuous 100%.
export async function assertLedgerScope(
  repo: any,
  records: readonly LcovRecord[],
  options: { label: string; scope: string; sourceGlob: string },
): Promise<void> {
  const foreign = records.filter(record => !record.file.startsWith(options.scope));
  if (foreign.length > 0) {
    throw new Error(
      `${options.label}: the ledger measured files outside ${options.scope}: ${foreign.map(record => record.file).join(', ')}`,
    );
  }

  const sources = await repo.glob(options.sourceGlob);
  if (sources.length === 0) {
    throw new Error(`${options.label}: no source file matches ${options.sourceGlob}, so the ledger has no subject`);
  }
  const measured = new Set(records.map(record => record.file));
  const absent = sources.filter((path: string) => !measured.has(path));
  if (absent.length > 0) {
    throw new Error(
      `${options.label}: these ${options.scope} files are absent from the ledger, not covered by it: ${absent.join(', ')}`,
    );
  }
}

export function assertAtLeast(records: readonly LcovRecord[], threshold: number, label: string): void {
  const lines = lineRate(records);
  const functions = functionRate(records);
  if (lines < threshold || functions < threshold) {
    throw new Error(
      `${label}: the ledger is below its declared threshold ${threshold} (lines ${lines.toFixed(4)}, functions ${functions.toFixed(4)})`,
    );
  }
}

export function assertBelow(records: readonly LcovRecord[], threshold: number, label: string): void {
  const lines = lineRate(records);
  if (lines >= threshold) {
    throw new Error(
      `${label}: the sabotage did not drive the ledger below its threshold ${threshold} (lines ${lines.toFixed(4)})`,
    );
  }
}

// The number sizing the sabotage must be the number the gate enforces, so it is read from the tier.
export function parseCoverageThreshold(source: string): CoverageThreshold | undefined {
  const declared: Record<string, number> = {};

  const scalar = source.match(/^[ \t]*coverageThreshold[ \t]*=[ \t]*([0-9]*\.?[0-9]+)[ \t]*(?:#.*)?$/m);
  if (scalar) {
    declared.threshold = Number(scalar[1]);
  }

  const inline = source.match(/^[ \t]*coverageThreshold[ \t]*=[ \t]*\{([^}]*)\}/m);
  // Deliberately not multiline: `$` has to mean end of input so the sub-table body is read whole.
  const table = source.match(/(?:^|\n)\[[^\]\n]*\.coverageThreshold\][ \t]*\n([\s\S]*?)(?=\n\[|$)/);
  for (const body of [inline?.[1], table?.[1]]) {
    if (body === undefined) continue;
    for (const entry of body.matchAll(/([A-Za-z_]+)[ \t]*=[ \t]*([0-9]*\.?[0-9]+)/g)) {
      declared[entry[1]] = Number(entry[2]);
    }
  }

  const values = Object.values(declared);
  if (values.length === 0) {
    return undefined;
  }
  return { effective: Math.max(...values), declared };
}

export async function readCoverageThreshold(repo: any, configPath: string, label: string): Promise<CoverageThreshold> {
  const threshold = parseCoverageThreshold(await repo.read(configPath));
  if (!threshold) {
    throw new Error(
      `${label}: ${configPath} declares no coverageThreshold, so the tier has no blocking coverage gate to prove`,
    );
  }
  if (threshold.effective <= 0 || threshold.effective > 1) {
    throw new Error(`${label}: ${configPath} declares an out-of-range coverageThreshold: ${threshold.effective}`);
  }
  return threshold;
}

// Derived from the measured baseline, so the fault is decisive at whatever threshold is declared.
export function uncoveredLinesNeeded(records: readonly LcovRecord[], threshold: number): number {
  const found = records.reduce((total, record) => total + record.linesFound, 0);
  const hit = records.reduce((total, record) => total + record.linesHit, 0);
  const minimumTotal = hit / threshold;
  // +1 clears the strict inequality; +2 absorbs the gap between emitted and instrumented lines.
  return Math.max(1, Math.floor(minimumTotal - found) + 3);
}

// A brand-new module nothing imports never enters a Bun ledger, so the fault rides an existing file.
export function uncoveredSourceBlock(symbol: string, uncoveredLines: number): string {
  const statements = Array.from({ length: Math.max(1, uncoveredLines) }, (_, index) => `  total += ${index + 1};`);
  return [
    '',
    `// Probe sabotage: ${symbol} is never called, so every line below is uncovered.`,
    `export function ${symbol}(seed: number): number {`,
    '  let total = seed;',
    ...statements,
    '  return total;',
    '}',
    '',
  ].join('\n');
}

export async function plantUncoveredLines(
  repo: any,
  path: string,
  symbol: string,
  uncoveredLines: number,
): Promise<MutationResult> {
  const source = await repo.read(path);
  await repo.write(path, `${source.trimEnd()}\n${uncoveredSourceBlock(symbol, uncoveredLines)}`);
  return { path };
}

// The write path is left intact so the round-trip through the real dependency is the only casualty.
export async function breakAdapterRead(repo: any, options?: { globs?: string[] }): Promise<MutationResult> {
  const globs = options?.globs ?? ['src/adapters/**/*.ts'];
  const paths = new Set<string>();
  for (const glob of globs) {
    for (const path of await repo.glob(glob)) {
      paths.add(path);
    }
  }

  const opening = /(\n[ \t]*(?:public[ \t]+)?async[ \t]+get[A-Za-z0-9_]*[ \t]*\([^)]*\)[^{\n]*\{\n)/;
  for (const path of [...paths].sort()) {
    const source = await repo.read(path);
    if (!opening.test(source)) {
      continue;
    }
    await repo.write(path, source.replace(opening, '$1    return null;\n'));
    return { path };
  }
  throw new Error(`no structural adapter read method found in ${globs.join(', ')}`);
}

// Glob-selected rather than sample-named, so swapping the sample cannot silently disarm it.
export async function plantDeadExport(
  repo: any,
  options?: { globs?: string[]; symbol?: string },
): Promise<MutationResult> {
  const globs = options?.globs ?? ['src/lib/**/*.ts'];
  const symbol = options?.symbol ?? 'probeDeadExport';
  for (const glob of globs) {
    const paths = (await repo.glob(glob)).sort();
    if (paths.length === 0) continue;
    const path = paths[0];
    const source = await repo.read(path);
    await repo.write(path, `${source.trimEnd()}\n\nexport const ${symbol} = (): number => 1;\n`);
    return { path };
  }
  throw new Error(`no source file found for a dead export in ${globs.join(', ')}`);
}

// Snapshots carry only tracked content, so dependencies are installed once instead of per row.
export const BUN_PROBE_SETUP = {
  pre: [
    'nix develop --no-write-lock-file .#ci -c true',
    'nix develop --no-write-lock-file .#ci -c bun install --frozen-lockfile',
  ],
};

export const BUN_PROBE_SANDBOX = { snapshot: 'git', preserve: ['.direnv', 'node_modules'] };
