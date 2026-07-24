import { describe, expect, test } from 'bun:test';

type BunTestConfig = {
  test?: {
    coveragePathIgnorePatterns?: string[];
  };
};

describe('Bun integration coverage policy', () => {
  test('excludes known glue while preserving the adapters-only ledger', async () => {
    const source = await Bun.file(new URL('../../bunfig.int.toml', import.meta.url)).text();
    const config = Bun.TOML.parse(source) as BunTestConfig;
    const ignored = config.test?.coveragePathIgnorePatterns ?? [];

    expect(ignored).toContain('src/index.ts');
    expect(ignored).toContain('src/sample.ts');
    expect(ignored).toContain('src/lib/**');
    expect(ignored).toContain('tests/**');
    expect(ignored).not.toContain('src/adapters/**');
  });
});
