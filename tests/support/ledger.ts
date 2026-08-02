import { resolve } from 'node:path';
import { Glob } from 'bun';

const REPOSITORY_ROOT = resolve(import.meta.dir, '../..');

/**
 * Import every module in a coverage ledger's scope so the report covers *all* files in that tier,
 * not only the ones a test happened to reach. Without this a source file with no test at all is
 * simply absent from the report, and an all-files threshold silently passes over it.
 *
 * Run from a bunfig `preload`, before any test file loads.
 */
export async function loadLedger(scope: string): Promise<void> {
  const modules = new Glob('**/*.ts');
  for await (const module of modules.scan({ cwd: resolve(REPOSITORY_ROOT, scope), absolute: true })) {
    await import(module);
  }
}
