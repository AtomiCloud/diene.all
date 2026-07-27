// COST CLASS: medium (<3min) — regenerates the schema from the Go structs, which
// compiles the generator and its config dependency tree. A lighter proxy cannot
// prove this mechanism: the property under test is that the COMMITTED schema equals
// what the CURRENT Go types produce, and only running the generator establishes
// that. Pattern-matching the committed file would prove nothing about the types.
import { expectRed } from './lib/helpers.ts';

const CHECK = "nix develop .#ci -c bash -lc './scripts/validate/schema-drift.sh'";

export default {
  contractVersion: 1,
  sandbox: { snapshot: 'git', preserve: ['.direnv'] },
  probes: [
    {
      name: 'baseline-config-schema-gen-check-green',
      description: 'The committed generated schema matches what the Go configuration structs produce.',
      kind: 'baseline',
      async run(repo: any) {
        const result = await repo.exec(CHECK, { timeoutMs: 600000 });
        const transcript = `${result.stdout ?? ''}\n${result.stderr ?? ''}`;
        if (result.exitCode !== 0) {
          throw new Error(`config-schema-gen-check failed on the healthy repo:\n${transcript}`);
        }
        // Assert on printed VALUES: the gate prints both sha256 digests, so the
        // healthy run must show two REAL digests that are EQUAL. Two empty files
        // also compare equal, which is exactly the vacuity this catches — a digest
        // of the empty string is a known constant and is refused.
        const committed = transcript.match(/committed ([0-9a-f]{64})/);
        const generated = transcript.match(/generated ([0-9a-f]{64})/);
        if (!committed || !generated) {
          throw new Error(
            `config-schema-gen-check exited 0 without printing both digests — refusing a silent pass:\n${transcript}`,
          );
        }
        const EMPTY_SHA256 = 'e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855';
        if (committed[1] === EMPTY_SHA256 || generated[1] === EMPTY_SHA256) {
          throw new Error('config-schema-gen-check compared EMPTY content — a zero-byte comparison is vacuous');
        }
        if (committed[1] !== generated[1]) {
          throw new Error(`config-schema-gen-check digests differ: ${committed[1]} vs ${generated[1]}`);
        }
      },
    },
    {
      name: 'mutation-config-schema-gen-check-caught',
      description: 'A drifted committed schema turns the gen-check red.',
      kind: 'mutation',
      expectedImpact: [],
      async run(repo: any) {
        // ONE fault: drift the COMMITTED artifact so it no longer matches the Go
        // types. Structural target — the generated schema is selected by glob and
        // the drift is a semantic change to a required-key list, not a deletion of
        // the file (deleting the subject would not qualify as a sabotage, and the
        // gate would refuse it as an empty comparison anyway).
        const paths = (await repo.glob('schemas/*.schema.json')).sort();
        if (paths.length === 0) {
          throw new Error('no generated configuration schema found');
        }
        const path = paths[0];
        const schema = JSON.parse(await repo.read(path));
        if (!Array.isArray(schema.required) || schema.required.length === 0) {
          throw new Error(`no structural required-key list found in ${path}`);
        }
        schema.required = [...schema.required, 'probeDriftedBlock'];
        await repo.write(path, `${JSON.stringify(schema, null, 2)}\n`);
        await expectRed(repo, CHECK, 'config-schema-gen-check');
      },
    },
  ],
};
