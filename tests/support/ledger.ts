import { resolve } from 'node:path';
import { Glob } from 'bun';

const REPOSITORY_ROOT = resolve(import.meta.dir, '../..');

/** Import every scoped module so untested files remain visible to the coverage threshold. */
export async function loadLedger(scope: string): Promise<void> {
  const modules = new Glob('**/*.ts');
  for await (const module of modules.scan({ cwd: resolve(REPOSITORY_ROOT, scope), absolute: true })) {
    await import(module);
  }
}
