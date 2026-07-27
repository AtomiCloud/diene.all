// COST CLASS: light (<30s) — a yq extraction plus a bounded ripgrep sweep of the
// shipped Go source; nothing compiles.
//
// The mechanism is `scripts/validate/rebrand.sh`: R21 says identity/branding and
// SSO/auth endpoints must be CONFIGURATION-DRIVEN, so no value declared in a
// committed config layer may appear as a string literal in shipped Go source.
import { expectRed } from './lib/helpers.ts';

const CHECK = "nix develop .#ci -c bash -lc './scripts/validate/rebrand.sh'";

export default {
  contractVersion: 1,
  sandbox: { snapshot: 'git', preserve: ['.direnv'] },
  probes: [
    {
      name: 'baseline-rebrand-static-guard-green',
      description:
        'Identity, branding, and SSO/auth values stay config-driven; the guard passes with its counts printed.',
      kind: 'baseline',
      async run(repo: any) {
        const result = await repo.exec(CHECK, { timeoutMs: 240000 });
        const transcript = `${result.stdout ?? ''}\n${result.stderr ?? ''}`;
        if (result.exitCode !== 0) {
          throw new Error(`rebrand-static-guard failed on the healthy repo:\n${transcript}`);
        }
        // Assert on printed VALUES and refuse a ZERO scan. A `grep`-shaped guard
        // that found nothing is indistinguishable from a guard that had nothing to
        // search: zero identity values, or zero shipped Go files, both yield "0
        // offenses". Both are refused explicitly.
        const scanned = transcript.match(/(\d+) identity\/auth values from (\d+) config files, (\d+) shipped Go files/);
        if (!scanned) {
          throw new Error(
            `rebrand-static-guard exited 0 without printing its scan counts — refusing a silent pass:\n${transcript}`,
          );
        }
        const [, values, configFiles, goFiles] = scanned;
        if (Number(values) === 0 || Number(configFiles) === 0 || Number(goFiles) === 0) {
          throw new Error(
            `rebrand-static-guard passed on an EMPTY scan (${values} values, ${configFiles} config files, ${goFiles} Go files)`,
          );
        }
        if (!transcript.includes('0 hardcoded identity/auth values in shipped Go source')) {
          throw new Error(
            `rebrand-static-guard exited 0 without asserting zero offenses — refusing a silent pass:\n${transcript}`,
          );
        }
      },
    },
    {
      name: 'mutation-rebrand-static-guard-caught',
      description: 'ONE hardcoded identity or SSO value in shipped Go source turns the guard red.',
      kind: 'mutation',
      expectedImpact: [],
      async run(repo: any) {
        // ONE fault: hardcode a single value the configuration already declares.
        // The value is READ FROM CONFIG rather than written as a literal here, so
        // the probe cannot drift when the identity is rebranded — and the target
        // file is chosen by GLOB over the shipped Go roots, never by sample name.
        const settings = (await repo.glob('config/settings.yaml')).sort();
        if (settings.length === 0) {
          throw new Error('no base configuration found');
        }
        const source = await repo.read(settings[0]);
        // The gate's own subject list starts at `app.service`; take that value
        // straight out of the YAML with a structural match on the app block.
        const app = source.match(/^app:\n(?:[ \t]+.*\n)*?[ \t]+service:[ \t]*(\S+)[ \t]*$/m);
        const identity = app?.[1]?.replace(/^['"]|['"]$/g, '');
        if (!identity) {
          throw new Error('could not resolve the configured service identity from the app block');
        }
        const targets = (await repo.glob('adapters/**/*.go')).filter(path => !path.endsWith('_test.go')).sort();
        if (targets.length === 0) {
          throw new Error('no structural shipped adapter target found');
        }
        const path = targets[0];
        const adapter = await repo.read(path);
        await repo.write(
          path,
          `${adapter.trimEnd()}\n\n// ProbeHardcodedIdentity violates R21 on purpose.\nconst ProbeHardcodedIdentity = "${identity}"\n`,
        );
        await expectRed(repo, CHECK, 'rebrand-static-guard');
      },
    },
  ],
};
