import { mkdir, open, rename, rm, stat } from 'node:fs/promises';
import { dirname, isAbsolute, resolve } from 'node:path';
import type { IFileSystem } from '../../lib/release/ports';

function absolutePath(root: string, path: string): string {
  return isAbsolute(path) ? path : resolve(root, path);
}

function normalizedGitPath(path: string): string {
  return path.replaceAll('\\', '/').replace(/^\.\//, '');
}

export class BunFileSystem implements IFileSystem {
  constructor(private readonly root: string) {}

  async readText(path: string): Promise<string> {
    const file = Bun.file(absolutePath(this.root, path));
    if (!(await file.exists())) throw new Error(`file not found: ${path}`);
    return file.text();
  }

  async readTextIfExists(path: string): Promise<string | null> {
    const file = Bun.file(absolutePath(this.root, path));
    return (await file.exists()) ? file.text() : null;
  }

  async writeAtomic(path: string, content: string): Promise<void> {
    const target = absolutePath(this.root, path);
    await mkdir(dirname(target), { recursive: true });
    let mode = 0o666;
    try {
      mode = (await stat(target)).mode & 0o777;
    } catch {
      // A new ordinary data file uses the process umask applied to 0666.
    }
    const temporary = `${target}.tmp-${process.pid}-${crypto.randomUUID()}`;
    const handle = await open(temporary, 'wx', mode);
    try {
      await handle.writeFile(content, 'utf8');
      await handle.sync();
      await handle.close();
      await rename(temporary, target);
    } catch (error) {
      await handle.close().catch(() => undefined);
      await rm(temporary).catch(() => undefined);
      throw error;
    }
  }

  async exists(path: string): Promise<boolean> {
    return Bun.file(absolutePath(this.root, path)).exists();
  }

  async remove(path: string): Promise<void> {
    await rm(absolutePath(this.root, path));
  }

  async hashIfExists(path: string): Promise<string | null> {
    const file = Bun.file(absolutePath(this.root, path));
    if (!(await file.exists())) return null;
    const hasher = new Bun.CryptoHasher('sha256');
    hasher.update(await file.arrayBuffer());
    return hasher.digest('hex');
  }

  matchesAny(path: string, patterns: readonly string[]): boolean {
    const normalized = normalizedGitPath(path);
    return patterns.some(pattern => {
      const candidate = normalizedGitPath(pattern);
      return candidate === normalized || new Bun.Glob(candidate).match(normalized);
    });
  }
}
