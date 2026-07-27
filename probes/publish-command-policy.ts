// Gate (static policy): the publish entrypoint (scripts/ci/publish.sh) must run
// the manifest==tag guard BEFORE it publishes, must publish from the
// diene_config member directory, and must publish exactly once.
//
// The previous implementation asked three independent `source.includes(...)`
// questions. That cannot see ORDER, cannot distinguish code from a comment, and
// cannot notice a duplicate publish — so moving the guard after
// `dart pub publish`, or leaving the required strings behind only in comments,
// kept this gate green while R-E43's approved publish entrypoint was no longer
// actually proved. This version strips comments and asserts an exact ordered
// shape over the remaining executable lines.
const PUBLISH_SH = 'scripts/ci/publish.sh';
const MEMBER = 'packages/diene_config';
const GUARD = 'scripts/validate/publish-version.sh';
const PUBLISH = 'dart pub publish --force';

// Executable lines only: a comment cannot satisfy a policy about what the
// script DOES.
function executableLines(source: string): string[] {
  return source
    .split('\n')
    .map(line => line.trim())
    .filter(line => line.length > 0 && !line.startsWith('#'));
}

function policyViolation(source: string): string | null {
  const lines = executableLines(source);

  const guardIdx = lines.findIndex(l => l.includes(GUARD));
  if (guardIdx === -1) return 'the manifest==tag guard is not invoked in executable code';

  const publishIdxs: number[] = [];
  lines.forEach((l, i) => {
    if (l.includes(PUBLISH)) publishIdxs.push(i);
  });
  if (publishIdxs.length === 0) return 'no publish command in executable code';
  if (publishIdxs.length > 1) return `publish runs ${publishIdxs.length} times; exactly one is allowed`;
  const publishIdx = publishIdxs[0];

  if (guardIdx > publishIdx) return 'the guard runs AFTER publish; the tag/manifest match must be verified first';

  // The publish must happen from the member directory, so the last `cd` before
  // the publish line has to target it.
  const cdBefore = lines.slice(0, publishIdx).filter(l => l.startsWith('cd '));
  if (cdBefore.length === 0) return 'publish is not preceded by a cd into the member directory';
  const lastCd = cdBefore[cdBefore.length - 1];
  if (!lastCd.includes(MEMBER)) return `the last cd before publish targets '${lastCd}', not ${MEMBER}`;

  return null;
}

const commandPolicyHolds = (source: string): boolean => policyViolation(source) === null;

export default {
  contractVersion: 1,
  sandbox: { snapshot: 'git' },
  probes: [
    {
      name: 'baseline-publish-command-policy-green',
      description: 'the guard precedes exactly one publish, run from the diene_config member directory',
      kind: 'baseline',
      async run(repo: any) {
        const violation = policyViolation(await repo.read(PUBLISH_SH));
        if (violation !== null) {
          throw new Error(`publish-command-policy: baseline violates the publish command policy: ${violation}`);
        }
      },
    },
    {
      name: 'mutation-publish-command-policy-caught',
      description: 'the policy check detects the publish directory being redirected away from the member',
      kind: 'mutation',
      expectedImpact: [],
      async run(repo: any) {
        const source = await repo.read(PUBLISH_SH);
        if (!commandPolicyHolds(source)) {
          throw new Error('publish-command-policy: policy already broken before sabotage');
        }
        await repo.write(PUBLISH_SH, source.replace('cd "${root_dir}/packages/diene_config"', 'cd "${root_dir}"'));
        if (commandPolicyHolds(await repo.read(PUBLISH_SH))) {
          throw new Error('publish-command-policy: policy survived sabotage');
        }
      },
    },
    {
      name: 'mutation-guard-moved-after-publish-caught',
      description: 'reordering the manifest guard to run after publication is detected',
      kind: 'mutation',
      expectedImpact: [],
      async run(repo: any) {
        const source = await repo.read(PUBLISH_SH);
        const lines = source.split('\n');
        const guardLine = lines.find(l => l.includes(GUARD) && !l.trim().startsWith('#'));
        if (guardLine === undefined) {
          throw new Error('publish-command-policy: no executable guard line to move');
        }
        const rest = lines.filter(l => l !== guardLine);
        const publishAt = rest.findIndex(l => l.includes(PUBLISH) && !l.trim().startsWith('#'));
        rest.splice(publishAt + 1, 0, guardLine);
        const mutated = rest.join('\n');
        if (commandPolicyHolds(mutated)) {
          throw new Error('publish-command-policy: a guard running after publish survived the policy check');
        }
        await repo.write(PUBLISH_SH, mutated);
      },
    },
    {
      name: 'mutation-guard-only-in-comment-caught',
      description: 'satisfying the guard string from a comment alone is detected',
      kind: 'mutation',
      expectedImpact: [],
      async run(repo: any) {
        const source = await repo.read(PUBLISH_SH);
        const mutated = source
          .split('\n')
          .map(l => (l.includes(GUARD) && !l.trim().startsWith('#') ? `# ${l}` : l))
          .join('\n');
        if (commandPolicyHolds(mutated)) {
          throw new Error('publish-command-policy: a commented-out guard still satisfied the policy');
        }
        await repo.write(PUBLISH_SH, mutated);
      },
    },
    {
      name: 'mutation-duplicate-publish-caught',
      description: 'a second, unguarded publish command is detected',
      kind: 'mutation',
      expectedImpact: [],
      async run(repo: any) {
        const source = await repo.read(PUBLISH_SH);
        const mutated = `${source}\n${PUBLISH}\n`;
        if (commandPolicyHolds(mutated)) {
          throw new Error('publish-command-policy: a duplicate publish survived the policy check');
        }
        await repo.write(PUBLISH_SH, mutated);
      },
    },
  ],
};
