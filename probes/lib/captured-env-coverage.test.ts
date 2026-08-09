import { describe, expect, test } from 'bun:test';
import { readdirSync, readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { join } from 'node:path';

// Stage-2 claims that every command which enters a development shell now goes through
// capturedEnvCommand. That claim is only worth anything if it cannot silently rot, so it
// is asserted against the source rather than trusted: a new probe that calls repo.exec
// with a `nix develop` command and forgets the wrapper fails here instead of quietly
// paying the entry cost the pilot exists to remove.
const probesDir = fileURLToPath(new URL('../', import.meta.url));
const probeFiles = readdirSync(probesDir)
  .filter(name => name.endsWith('.ts'))
  .sort();

const CONST_WITH_ENTRY = /^const\s+([A-Za-z_$][\w$]*)\s*=\s*(['"`])([\s\S]*?)\2;/gm;

type Site = { file: string; wrapped: boolean; snippet: string };

function execSites(file: string, source: string): Site[] {
  const entryConsts = new Set<string>();
  for (const match of source.matchAll(CONST_WITH_ENTRY)) {
    if (match[3].includes('nix develop')) entryConsts.add(match[1]);
  }

  const sites: Site[] = [];
  for (const match of source.matchAll(/repo\.exec\(\s*/g)) {
    const rest = source.slice(match.index + match[0].length);
    if (rest.startsWith('capturedEnvCommand(')) {
      const inner = rest.slice('capturedEnvCommand('.length, 400);
      const isEntry = entryConsts.has(inner.match(/^[A-Za-z_$][\w$]*/)?.[0] ?? '') || inner.includes('nix develop');
      if (isEntry) sites.push({ file, wrapped: true, snippet: inner.slice(0, 60) });
      continue;
    }
    const identifier = rest.match(/^[A-Za-z_$][\w$]*/)?.[0];
    if (identifier && entryConsts.has(identifier)) {
      sites.push({ file, wrapped: false, snippet: identifier });
      continue;
    }
    const literal = rest.match(/^(['"`])((?:\\.|(?!\1)[\s\S])*?)\1/);
    if (literal?.[2].includes('nix develop')) {
      sites.push({ file, wrapped: false, snippet: literal[2].slice(0, 60) });
    }
  }
  return sites;
}

const allSites = probeFiles.flatMap(file => execSites(file, readFileSync(join(probesDir, file), 'utf8')));

describe('captured-env coverage of direct repo.exec shell entries', () => {
  test('no probe enters a development shell without going through capturedEnvCommand', () => {
    const unwrapped = allSites.filter(site => !site.wrapped).map(site => `${site.file}: ${site.snippet}`);
    expect(unwrapped).toEqual([]);
  });

  // The count is a tripwire, not a target: it exists so that ADDING a shell-entering
  // call site is a decision somebody makes on purpose. The population it names is every
  // `repo.exec` in `probes/*.ts` whose command enters a development shell, so deleting a
  // probe lowers it and a new direct site raises it. Move it only together with the sites
  // that justify it — a number left one too high is an assertion that fails silently.
  // The two `hook-` files hold a direct site each so their mutation arms can assert the
  // gate's refusal TEXT and not merely its exit code.
  test('the wrapped set is the 10 known shell-entering call sites, across 6 files', () => {
    const wrapped = allSites.filter(site => site.wrapped);
    expect(wrapped).toHaveLength(10);
    expect([...new Set(wrapped.map(site => site.file))].sort()).toEqual([
      'hook-enforce-exec.ts',
      'hook-shellcheck.ts',
      'precommit-treefmt-actionlint.ts',
      'precommit-treefmt-nixfmt.ts',
      'precommit-treefmt-prettier.ts',
      'precommit-treefmt-shfmt.ts',
    ]);
  });

  // The exemption lives on the label, so it only holds while both features keep reaching
  // helpers that pass one. dev-shell now uses the shared once-per-phase helper, while
  // direnv retains its own labelled expectGreen call.
  test('dev-shell and direnv still enter their shells through labelled helpers', () => {
    const devShell = readFileSync(join(probesDir, 'dev-shell.ts'), 'utf8');
    expect(devShell).toContain("import { expectDevShellsOnce } from './lib/helpers.ts'");
    expect(devShell).not.toContain('capturedEnvCommand');
    expect(devShell).toContain('await expectDevShellsOnce(repo);');

    const direnv = readFileSync(join(probesDir, 'direnv.ts'), 'utf8');
    expect(direnv).toContain("from './lib/helpers.ts'");
    expect(direnv).not.toContain('capturedEnvCommand');
    expect(direnv).toContain("'direnv',");

    const helpers = readFileSync(join(probesDir, 'lib/helpers.ts'), 'utf8');
    expect(helpers).toContain("new Set(['dev-shell', 'direnv'])");
    expect(helpers).toContain("await expectGreen(repo, DEV_SHELL_CHAIN, 'dev-shell');");
  });
});
