import { describe, expect, test } from 'bun:test';
import {
  assertAtLeast,
  assertBelow,
  assertLedgerScope,
  breakAdapterRead,
  functionRate,
  lineRate,
  parseCoverageThreshold,
  parseLcov,
  plantDeadExport,
  plantUncoveredLines,
  uncoveredLinesNeeded,
  uncoveredSourceBlock,
} from './bun';

class FakeRepo {
  readonly files = new Map<string, string>();

  constructor(files: Record<string, string>) {
    for (const [path, content] of Object.entries(files)) {
      this.files.set(path, content);
    }
  }

  async read(path: string): Promise<string> {
    const content = this.files.get(path);
    if (content === undefined) {
      throw new Error(`missing fake file: ${path}`);
    }
    return content;
  }

  async write(path: string, content: string): Promise<void> {
    this.files.set(path, content);
  }

  // Only the two directory prefixes these helpers select on need to resolve.
  async glob(pattern: string): Promise<string[]> {
    const prefix = pattern.slice(0, pattern.indexOf('**'));
    return [...this.files.keys()].filter(path => path.startsWith(prefix) && path.endsWith('.ts')).sort();
  }
}

function record(file: string, linesFound: number, linesHit: number): string {
  return [`SF:${file}`, 'FNF:2', 'FNH:2', `LF:${linesFound}`, `LH:${linesHit}`, 'end_of_record', ''].join('\n');
}

describe('lcov ledger parsing', () => {
  test('reads every counter of every record', () => {
    const actual = parseLcov(`${record('src/lib/a.ts', 10, 10)}${record('src/lib/b.ts', 4, 2)}`);

    expect(actual).toHaveLength(2);
    expect(actual[0]).toEqual({
      file: 'src/lib/a.ts',
      linesFound: 10,
      linesHit: 10,
      functionsFound: 2,
      functionsHit: 2,
    });
    expect(lineRate(actual)).toBeCloseTo(12 / 14, 6);
    expect(functionRate(actual)).toBe(1);
  });

  test('refuses an empty ledger instead of reporting it as clean', () => {
    expect(() => parseLcov('TN:\n')).toThrow('the coverage ledger is empty');
  });

  test('refuses a record whose line counters were never emitted', () => {
    expect(() => parseLcov('SF:src/lib/a.ts\nFNF:1\nFNH:1\nend_of_record\n')).toThrow(
      'lcov record for src/lib/a.ts declares no LF',
    );
  });
});

describe('ledger scope assertions', () => {
  const sources = {
    'src/lib/a.ts': '',
    'src/lib/b.ts': '',
  };

  test('accepts a ledger that measures the whole tier and nothing else', async () => {
    const repo = new FakeRepo(sources);
    const records = parseLcov(`${record('src/lib/a.ts', 4, 4)}${record('src/lib/b.ts', 4, 4)}`);

    await assertLedgerScope(repo, records, {
      label: 'unit-coverage',
      scope: 'src/lib/',
      sourceGlob: 'src/lib/**/*.ts',
    });
  });

  test('rejects a ledger that reaches outside its tier', async () => {
    const repo = new FakeRepo(sources);
    const records = parseLcov(`${record('src/lib/a.ts', 4, 4)}${record('src/adapters/x.ts', 4, 4)}`);

    await expect(
      assertLedgerScope(repo, records, {
        label: 'unit-coverage',
        scope: 'src/lib/',
        sourceGlob: 'src/lib/**/*.ts',
      }),
    ).rejects.toThrow('measured files outside src/lib/: src/adapters/x.ts');
  });

  test('rejects a tier file that is absent from the ledger rather than covered by it', async () => {
    const repo = new FakeRepo(sources);
    const records = parseLcov(record('src/lib/a.ts', 4, 4));

    await expect(
      assertLedgerScope(repo, records, {
        label: 'unit-coverage',
        scope: 'src/lib/',
        sourceGlob: 'src/lib/**/*.ts',
      }),
    ).rejects.toThrow('absent from the ledger, not covered by it: src/lib/b.ts');
  });

  test('rejects a tier with no source file at all', async () => {
    const repo = new FakeRepo({});
    const records = parseLcov(record('src/lib/a.ts', 4, 4));

    await expect(
      assertLedgerScope(repo, records, {
        label: 'unit-coverage',
        scope: 'src/lib/',
        sourceGlob: 'src/lib/**/*.ts',
      }),
    ).rejects.toThrow('no source file matches src/lib/**/*.ts');
  });
});

describe('threshold assertions', () => {
  test('assertAtLeast accepts a ledger at its threshold and rejects one under it', () => {
    const green = parseLcov(record('src/lib/a.ts', 10, 10));
    const red = parseLcov(record('src/lib/a.ts', 10, 9));

    expect(() => assertAtLeast(green, 1, 'unit-coverage')).not.toThrow();
    expect(() => assertAtLeast(red, 1, 'unit-coverage')).toThrow('below its declared threshold 1');
  });

  test('assertBelow rejects a sabotage that left the ledger at threshold', () => {
    const untouched = parseLcov(record('src/lib/a.ts', 10, 10));

    expect(() => assertBelow(untouched, 1, 'unit-coverage')).toThrow('did not drive the ledger below its threshold 1');
  });
});

describe('declared coverage threshold', () => {
  test('reads the scalar form', () => {
    expect(parseCoverageThreshold('[test]\ncoverageThreshold = 0.85\n')).toEqual({
      effective: 0.85,
      declared: { threshold: 0.85 },
    });
  });

  test('reads an inline table and keeps the strictest component', () => {
    expect(parseCoverageThreshold('coverageThreshold = { line = 0.8, function = 0.95 }\n')).toEqual({
      effective: 0.95,
      declared: { line: 0.8, function: 0.95 },
    });
  });

  test('reads a sub-table spelling', () => {
    const actual = parseCoverageThreshold('[test.coverageThreshold]\nline = 0.9\nstatement = 0.7\n\n[install]\n');

    expect(actual).toEqual({ effective: 0.9, declared: { line: 0.9, statement: 0.7 } });
  });

  test('ignores a commented-out declaration', () => {
    expect(parseCoverageThreshold('[test]\n# coverageThreshold = 0.9\n')).toBeUndefined();
  });

  test('reports absence rather than defaulting to a benign number', () => {
    expect(parseCoverageThreshold('[test]\nroot = "tests/unit"\n')).toBeUndefined();
  });
});

describe('coverage sabotage sizing', () => {
  test('sizes the fault from the measured baseline so it clears the threshold', () => {
    const records = parseLcov(record('src/lib/a.ts', 100, 80));

    // 80 hit lines can never reach 0.8 once the ledger holds more than 100 lines.
    const needed = uncoveredLinesNeeded(records, 0.8);

    expect(needed).toBeGreaterThan(0);
    expect(80 / (100 + needed)).toBeLessThan(0.8);
  });

  test('still asks for a fault when the tier already sits exactly at 100%', () => {
    const records = parseLcov(record('src/lib/a.ts', 40, 40));

    const needed = uncoveredLinesNeeded(records, 1);

    expect(needed).toBeGreaterThanOrEqual(1);
    expect(40 / (40 + needed)).toBeLessThan(1);
  });

  test('emits at least as many never-executed statements as it was asked for', () => {
    const block = uncoveredSourceBlock('probeUncovered', 5);

    expect(block.split('\n').filter(line => line.trim().startsWith('total +=')).length).toBe(5);
    expect(block).toContain('function probeUncovered(seed: number): number {');
  });

  // Orthogonality: the coverage fault must redden the coverage gate and nothing else.
  test('keeps the coverage fault unexported so it is not also an unused export', () => {
    const block = uncoveredSourceBlock('probeUncovered', 3);

    expect(block).not.toContain('export function probeUncovered');
    expect(block).not.toContain('export const probeUncovered');
  });

  test('references the coverage fault so it is not also an unused local', () => {
    const block = uncoveredSourceBlock('probeUncovered', 3);

    expect(block).toContain('void probeUncovered;');
  });

  test('appends the fault to the file the ledger already measures', async () => {
    const repo = new FakeRepo({ 'src/lib/a.ts': 'export const a = 1;\n' });

    const actual = await plantUncoveredLines(repo, 'src/lib/a.ts', 'probeUncovered', 2);

    expect(actual.path).toBe('src/lib/a.ts');
    expect(await repo.read('src/lib/a.ts')).toContain('export const a = 1;');
    expect(await repo.read('src/lib/a.ts')).toContain('function probeUncovered');
    expect(await repo.read('src/lib/a.ts')).not.toContain('export function probeUncovered');
  });
});

describe('structural source mutators', () => {
  test('makes the first adapter read method answer null before reaching its client', async () => {
    const repo = new FakeRepo({
      'src/adapters/redis-kv-store.ts': [
        'export class Store {',
        '  async get(key: string): Promise<string | null> {',
        '    return this.client.get(key);',
        '  }',
        '}',
        '',
      ].join('\n'),
    });

    const actual = await breakAdapterRead(repo);

    const source = await repo.read(actual.path);
    expect(source.indexOf('return null;')).toBeLessThan(source.indexOf('return this.client.get(key);'));
  });

  test('leaves the adapter write path intact so exactly one fault is planted', async () => {
    const repo = new FakeRepo({
      'src/adapters/redis-kv-store.ts': [
        'export class Store {',
        '  async set(key: string, value: string): Promise<void> {',
        '    await this.client.set(key, value);',
        '  }',
        '  async get(key: string): Promise<string | null> {',
        '    return this.client.get(key);',
        '  }',
        '}',
        '',
      ].join('\n'),
    });

    await breakAdapterRead(repo);

    expect(await repo.read('src/adapters/redis-kv-store.ts')).toContain('await this.client.set(key, value);');
  });

  test('reports a missing adapter target instead of silently mutating nothing', async () => {
    const repo = new FakeRepo({ 'src/adapters/kv-store.ts': 'export interface IStore {}\n' });

    await expect(breakAdapterRead(repo)).rejects.toThrow('no structural adapter read method found');
  });

  test('appends a dead export to a glob-selected domain file', async () => {
    const repo = new FakeRepo({ 'src/lib/a.ts': 'export const a = 1;\n' });

    const actual = await plantDeadExport(repo);

    expect(actual.path).toBe('src/lib/a.ts');
    expect(await repo.read('src/lib/a.ts')).toContain('export const probeDeadExport = 1;');
  });

  // Orthogonality: a dead export that is a function arrives in the unit ledger uncalled and takes
  // the coverage control down with it, so the row stops being evidence about Knip alone.
  test('keeps the dead export free of any function so coverage stays whole', async () => {
    const repo = new FakeRepo({ 'src/lib/a.ts': 'export const a = 1;\n' });

    await plantDeadExport(repo);

    const source = await repo.read('src/lib/a.ts');
    expect(source).not.toContain('=>');
    expect(source).not.toContain('function');
  });

  test('reports a missing dead-export target instead of silently mutating nothing', async () => {
    const repo = new FakeRepo({});

    await expect(plantDeadExport(repo)).rejects.toThrow('no source file found for a dead export');
  });
});
