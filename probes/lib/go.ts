import type { ProbeRepo } from '@cyanprint/contracts';

function directory(path: string): string {
  return path.slice(0, path.lastIndexOf('/'));
}

function packageName(source: string): string {
  const name = source.match(/^package\s+([A-Za-z0-9_]+)/m)?.[1];
  if (!name) {
    throw new Error('could not infer Go package');
  }
  return name;
}

async function first(repo: ProbeRepo, glob: string): Promise<string> {
  const paths = (await repo.glob(glob)).filter(path => !path.endsWith('_test.go')).sort();
  if (paths.length === 0) {
    throw new Error(`no structural Go target matched ${glob}`);
  }
  return paths[0];
}

export async function flipGoAssertion(repo: ProbeRepo): Promise<void> {
  const path = 'tests/unit/operator/note_test.go';
  const source = await repo.read(path);
  const target = 'require.Equal(t, "note-a-copy-2", note.CopyName("note-a", 2))';
  if (!source.includes(target)) {
    throw new Error('operator unit assertion target is missing');
  }
  await repo.write(path, source.replace(target, 'require.Equal(t, "probe-wrong", note.CopyName("note-a", 2))'));
}

export async function plantWhiteBoxTest(repo: ProbeRepo): Promise<void> {
  const paths = (await repo.glob('tests/**/*_test.go')).sort();
  if (paths.length === 0) {
    throw new Error('no Go test package found');
  }
  const source = await repo.read(paths[0]);
  const external = packageName(source);
  if (!external.endsWith('_test')) {
    throw new Error('healthy test package is not external');
  }
  await repo.write(
    `${directory(paths[0])}/probe_white_box_test.go`,
    `package ${external.slice(0, -5)}\n\nimport "testing"\n\nfunc TestProbeWhiteBox(t *testing.T) { t.Helper() }\n`,
  );
}

export async function breakAdapter(repo: ProbeRepo): Promise<void> {
  const path = 'adapters/operator/kube/resources.go';
  const source = await repo.read(path);
  const target = 'cm.Data[payloadKey] = payload';
  if (!source.includes(target)) {
    throw new Error('operator adapter write target is missing');
  }
  await repo.write(path, source.replace(target, 'cm.Data[payloadKey] = "probe-wrong"'));
}

export async function plantGoFile(
  repo: ProbeRepo,
  glob: string,
  filename: string,
  declaration: string,
): Promise<string> {
  const path = await first(repo, glob);
  const target = `${directory(path)}/${filename}`;
  await repo.write(target, `package ${packageName(await repo.read(path))}\n\n${declaration}\n`);
  return target;
}

export async function plantProductionOnlySymbol(repo: ProbeRepo): Promise<void> {
  const sourcePath = await plantGoFile(
    repo,
    'lib/**/*.go',
    'probe_production_only.go',
    'func ProbeProductionOnly() int { return 1 }',
  );
  const tests = (await repo.glob('tests/unit/**/*_test.go')).sort();
  if (tests.length === 0) {
    throw new Error('no unit test package found');
  }
  const module = (await repo.read('go.mod')).match(/^module\s+(\S+)/m)?.[1];
  if (!module) {
    throw new Error('Go module path is missing');
  }
  const sourceDirectory = directory(sourcePath);
  const importedPackage = packageName(await repo.read(sourcePath));
  const testPackage = packageName(await repo.read(tests[0]));
  await repo.write(
    `${directory(tests[0])}/probe_production_only_test.go`,
    `package ${testPackage}\n\nimport (\n\t"testing"\n\t"${module}/${sourceDirectory}"\n)\n\nfunc TestProbeProductionOnly(t *testing.T) {\n\tt.Helper()\n\tif ${importedPackage}.ProbeProductionOnly() != 1 { t.Fatal("probe") }\n}\n`,
  );
}

export async function unformatGo(repo: ProbeRepo): Promise<void> {
  const path = await first(repo, 'lib/**/*.go');
  const source = await repo.read(path);
  const signature = source.match(/^func ([A-Z][A-Za-z0-9_]*)\(([^)]*)\)([^\n{]*) \{$/m);
  if (!signature) {
    throw new Error('no exported Go function signature found');
  }
  const unformatted = `func ${signature[1]}( ${signature[2]} )${signature[3]}{`;
  await repo.write(path, source.replace(signature[0], unformatted));
}

export async function breakGoWorkflow(repo: ProbeRepo): Promise<void> {
  const paths = (await repo.glob('.github/workflows/⚡reusable-go-*.yaml')).sort();
  for (const path of paths) {
    const source = await repo.read(path);
    const match = source.match(/\.\/scripts\/ci\/[A-Za-z0-9._/-]+\.sh/);
    if (match) {
      await repo.write(path, source.replace(match[0], './scripts/ci/probe-missing.sh'));
      return;
    }
  }
  throw new Error('no Go workflow script target found');
}
