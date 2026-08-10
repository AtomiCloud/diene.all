import type { ProbeRepo } from '@cyanprint/contracts';

function directory(path: string): string {
  return path.slice(0, path.lastIndexOf('/'));
}

function packageName(source: string): string {
  const name = source.match(/^package\s+([A-Za-z0-9_]+)/m)?.[1];
  if (!name) throw new Error('could not infer Go package');
  return name;
}

async function firstSource(repo: ProbeRepo, glob: string): Promise<string> {
  const paths = (await repo.glob(glob))
    .filter(path => !path.endsWith('_test.go') && !path.includes('/tests/fixtures/'))
    .sort();
  if (paths.length === 0) throw new Error(`no Go source matched ${glob}`);
  return paths[0];
}

export async function plantVetMisuse(repo: ProbeRepo): Promise<void> {
  const path = await firstSource(repo, 'lib/**/*.go');
  const source = await repo.read(path);
  await repo.write(
    `${directory(path)}/probe_vet.go`,
    `package ${packageName(source)}\n\nimport "fmt"\n\nfunc ProbeVet() { fmt.Printf("%d", "not-an-integer") }\n`,
  );
}

export async function removeExportedSymbol(repo: ProbeRepo): Promise<void> {
  const paths = (await repo.glob('{lib,adapters,testhelper}/**/*.go'))
    .filter(path => !path.endsWith('_test.go'))
    .sort();
  for (const path of paths) {
    const source = await repo.read(path);
    const declaration = source.match(/^func ([A-Z][A-Za-z0-9_]*)\(/m);
    if (declaration) {
      await repo.write(path, source.replace(`func ${declaration[1]}(`, `func ${declaration[1]}Probe(`));
      return;
    }
  }
  throw new Error('no exported Go function found');
}

export async function removeExportDoc(repo: ProbeRepo): Promise<void> {
  const paths = (await repo.glob('{lib,adapters,testhelper}/**/*.go'))
    .filter(path => !path.endsWith('_test.go'))
    .sort();
  for (const path of paths) {
    const source = await repo.read(path);
    const documented = source.match(/^\/\/ ([A-Z][A-Za-z0-9_]*)[^\n]*\n(func|type) \1\b/m);
    if (documented) {
      await repo.write(path, source.replace(`${documented[0].split('\n')[0]}\n`, ''));
      return;
    }
  }
  throw new Error('no documented export found');
}

export async function breakExample(repo: ProbeRepo): Promise<void> {
  const paths = (await repo.glob('**/*_test.go')).sort();
  for (const path of paths) {
    const source = await repo.read(path);
    if (source.includes('// Output:')) {
      await repo.write(path, source.replace(/\/\/ Output: [^\n]+/, '// Output: probe-wrong-output'));
      return;
    }
  }
  throw new Error('no Go example output found');
}

export async function flipMetaAssertion(repo: ProbeRepo): Promise<void> {
  const paths = (await repo.glob('tests/meta/**/*_test.go')).sort();
  for (const path of paths) {
    const source = await repo.read(path);
    if (source.includes('got != want')) {
      await repo.write(path, source.replace('got != want', 'got == want'));
      return;
    }
  }
  throw new Error('no meta assertion target found');
}

export async function addUncoveredTestHelper(repo: ProbeRepo): Promise<void> {
  const path = await firstSource(repo, 'testhelper/**/*.go');
  const source = await repo.read(path);
  await repo.write(
    `${directory(path)}/probe_uncovered.go`,
    `package ${packageName(source)}\n\nfunc ProbeUncovered() bool { return true }\n`,
  );
}
