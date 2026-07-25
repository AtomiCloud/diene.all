import { expectGreen, expectRed } from './lib/helpers.ts';

const gate = 'nix develop .#ci -c pre-commit run a-golangci-lint --all-files';

export default {
  contractVersion: 1,
  sandbox: { snapshot: 'git', preserve: ['.direnv'] },
  probes: [
    {
      name: 'baseline-golangci-hook-green',
      description: 'The generated golangci-lint hook passes the healthy Go source.',
      kind: 'baseline',
      async run(repo: any) {
        await expectGreen(repo, gate, 'hook-golangci-lint');
      },
    },
    {
      name: 'mutation-golangci-hook-caught',
      description: 'A native ineffassign violation must turn the owning hook red.',
      kind: 'mutation',
      async run(repo: any) {
        // Inject into whichever package this library actually ships rather than
        // the template's own example package, which retargeted libraries drop.
        const source = (await repo.glob('lib/**/*.go')).find((path: string) => !path.endsWith('_test.go'));
        if (!source) throw new Error('no Go source file found under lib/');
        const pkg = (await repo.read(source)).match(/^package\s+(\w+)$/m);
        if (!pkg) throw new Error(`no package clause in ${source}`);
        await repo.write(
          `${source.slice(0, source.lastIndexOf('/'))}/probe_ineffassign.go`,
          `package ${pkg[1]}\n\nfunc probeIneffassign(value string) string {\n\tnormalized := value\n\tnormalized = value\n\treturn normalized\n}\n`,
        );
        await expectRed(repo, gate, 'hook-golangci-lint');
      },
    },
  ],
};
