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

// Returns the mutated path so the caller can restore exactly what it owns.
//
// The upstream structural matcher (`if x != y { t.Fatalf(`) finds NOTHING in this
// node: its unit tier asserts through testify `require`, so a discovered target
// would leave the mutation arm throwing instead of proving the tier. The sabotage
// is therefore pinned to this node's own assertion, and the `includes` guard makes
// a rename of that assertion loud rather than silently un-sabotaging the probe.
export async function flipGoAssertion(repo: ProbeRepo): Promise<string> {
  const path = 'tests/unit/operator/note_test.go';
  const source = await repo.read(path);
  const target = 'require.Equal(t, "note-a-copy-2", note.CopyName("note-a", 2))';
  if (!source.includes(target)) {
    throw new Error('operator unit assertion target is missing');
  }
  await repo.write(path, source.replace(target, 'require.Equal(t, "probe-wrong", note.CopyName("note-a", 2))'));
  return path;
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

// Returns the mutated path, same contract as flipGoAssertion above.
//
// The upstream matcher looks for a keyed `.Set(ctx, key, value, ttl)` write, which
// this node has no instance of — its adapter writes the payload into a ConfigMap.
// Pinned to that write for the same reason, with the same loud guard.
export async function breakAdapter(repo: ProbeRepo): Promise<string> {
  const path = 'adapters/operator/kube/resources.go';
  const source = await repo.read(path);
  const target = 'cm.Data[payloadKey] = payload';
  if (!source.includes(target)) {
    throw new Error('operator adapter write target is missing');
  }
  await repo.write(path, source.replace(target, 'cm.Data[payloadKey] = "probe-wrong"'));
  return path;
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

// Pick the target by SIGNATURE rather than by position: the first file under
// lib/**/*.go need not carry an exported function, and a test file must never be
// the one unformatted.
export async function unformatGo(repo: ProbeRepo): Promise<string> {
  const paths = (await repo.glob('lib/**/*.go')).filter(path => !path.endsWith('_test.go')).sort();
  for (const path of paths) {
    const source = await repo.read(path);
    const signature = source.match(/^func ([A-Z][A-Za-z0-9_]*)\(([^)]*)\)([^\n{]*) \{$/m);
    if (signature) {
      const unformatted = `func ${signature[1]}( ${signature[2]} )${signature[3]}{`;
      await repo.write(path, source.replace(signature[0], unformatted));
      return path;
    }
  }
  throw new Error('no Go file under lib/**/*.go carries an exported signature');
}
