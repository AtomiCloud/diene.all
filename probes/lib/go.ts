import type { ProbeRepo } from '@cyanprint/contracts';
import { restoreProbeState } from './helpers.ts';

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
  const paths = (await repo.glob('tests/unit/**/*_test.go')).sort();
  for (const path of paths) {
    const source = await repo.read(path);
    if (source.includes('; got != ')) {
      await repo.write(path, source.replace('; got != ', '; got == '));
      return;
    }
  }
  throw new Error('no structural Go assertion target found');
}

// Return the untracked fixture path so the caller can clean it precisely.
export async function plantWhiteBoxTest(repo: ProbeRepo): Promise<string> {
  const paths = (await repo.glob('tests/**/*_test.go')).sort();
  if (paths.length === 0) {
    throw new Error('no Go test package found');
  }
  const source = await repo.read(paths[0]);
  const external = packageName(source);
  if (!external.endsWith('_test')) {
    throw new Error('healthy test package is not external');
  }
  const target = `${directory(paths[0])}/probe_white_box_test.go`;
  await repo.write(
    target,
    `package ${external.slice(0, -5)}\n\nimport "testing"\n\nfunc TestProbeWhiteBox(t *testing.T) { t.Helper() }\n`,
  );
  return target;
}

export async function breakAdapter(repo: ProbeRepo): Promise<void> {
  const paths = (await repo.glob('adapters/**/*.go')).sort();
  for (const path of paths) {
    const source = await repo.read(path);
    const target = '.Set(ctx, key, value, 0)';
    if (source.includes(target)) {
      await repo.write(path, source.replace(target, '.Set(ctx, key+"-probe", value, 0)'));
      return;
    }
  }
  throw new Error('no structural adapter method target found');
}

// Resolve fallible metadata before writing, then return the exact fixture path.
export async function plantGoFile(
  repo: ProbeRepo,
  glob: string,
  filename: string,
  declaration: string,
): Promise<string> {
  const path = await first(repo, glob);
  const packageDeclaration = packageName(await repo.read(path));
  const target = `${directory(path)}/${filename}`;
  await repo.write(target, `package ${packageDeclaration}\n\n${declaration}\n`);
  return target;
}

// Return both halves of the test-only-reachability fixture for atomic cleanup.
export async function plantProductionOnlySymbol(repo: ProbeRepo): Promise<string[]> {
  const tests = (await repo.glob('tests/unit/**/*_test.go')).sort();
  if (tests.length === 0) {
    throw new Error('no unit test package found');
  }
  const module = (await repo.read('go.mod')).match(/^module\s+(\S+)/m)?.[1];
  if (!module) {
    throw new Error('Go module path is missing');
  }
  const testPackage = packageName(await repo.read(tests[0]));
  const sourcePath = await plantGoFile(
    repo,
    'lib/**/*.go',
    'probe_production_only.go',
    'func ProbeProductionOnly() int { return 1 }',
  );
  const planted = [sourcePath];
  try {
    const sourceDirectory = directory(sourcePath);
    const importedPackage = packageName(await repo.read(sourcePath));
    const testPath = `${directory(tests[0])}/probe_production_only_test.go`;
    await repo.write(
      testPath,
      `package ${testPackage}\n\nimport (\n\t"testing"\n\t"${module}/${sourceDirectory}"\n)\n\nfunc TestProbeProductionOnly(t *testing.T) {\n\tt.Helper()\n\tif ${importedPackage}.ProbeProductionOnly() != 1 { t.Fatal("probe") }\n}\n`,
    );
    planted.push(testPath);
    return planted;
  } catch (error) {
    await restoreProbeState(repo, planted);
    throw error;
  }
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
