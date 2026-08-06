import { describe, expect, test } from 'bun:test';
import { readdirSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { join } from 'node:path';

// Every probe module is imported here because nothing else imports them. The engine
// loads them at dispatch, so a module-scope throw costs a whole run: it fails before
// any arm, writes no REPORT.json, and yields zero arms rather than a red one.
//
// The gap this closes is specific. `bun test probes/` only runs `*.test.ts`, the
// pre-commit battery only runs hooks, and the captured-env census reads these files
// as TEXT rather than importing them - so all three passed while a probe module could
// not load at all. A String.raw block is the way it happened: String.raw suppresses
// escape processing, not interpolation, so a `${...}` inside one is read by JS, and
// one naming no JS binding throws ReferenceError at module scope.
const probesDir = fileURLToPath(new URL('../', import.meta.url));
const probeFiles = readdirSync(probesDir)
  .filter(name => name.endsWith('.ts'))
  .sort();

describe('every probe module loads', () => {
  test('the probe set is non-empty, so an empty glob cannot pass this vacuously', () => {
    expect(probeFiles.length).toBeGreaterThan(20);
  });

  for (const file of probeFiles) {
    test(`${file} imports without throwing`, async () => {
      const loaded = await import(join(probesDir, file));
      // A probe module that loads but exports no default would still be useless to
      // the engine, so assert the shape the engine actually reads.
      expect(loaded.default).toBeDefined();
      expect(Array.isArray(loaded.default.probes)).toBe(true);
    });
  }
});
