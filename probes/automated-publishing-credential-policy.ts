// Gate (static policy): publishing uses the long-lived AtomiCloud org credential
// `PUB_CREDENTIALS_JSON`, and the window in which that credential exists on disk
// must contain nothing but the approved publish. So this gate does not look for
// forbidden substrings — it pins the workflow's entire security-relevant
// execution shape and rejects everything else.
//
// `Bun.YAML.parse` gives the parsed document; the policy then requires an exact
// allow-list at every level: the workflow's top-level keys, its single trigger,
// its single `publish` job, that job's keys, and each of its five steps in order
// — key set, name, env mapping, and command sequence. Substring searching cannot
// certify this boundary. A step can read the credential without ever naming the
// file (`base64 "$HOME/.config/dart/"*`), spend it outside the approved
// entrypoint (`dart pub publish --force`), relocate it (`env: {HOME: /tmp}`), or
// neutralize its guard through control flow alone (`continue-on-error: true` on
// the write, `if: always()` on the publish). None of those spell anything a
// filter could match, so the only sound rule is: exactly these steps, exactly
// these keys, exactly these commands, in exactly this order.
const REUSABLE_PUBLISH = '.github/workflows/⚡reusable-publish.yaml';

const PUBLISH_JOB = 'publish';
const DEPLOY_ENVIRONMENT = 'pub.dev';
const CREDENTIAL_KEY = 'PUB_CREDENTIALS_JSON';
const CREDENTIAL_VALUE = '${{ secrets.PUB_CREDENTIALS_JSON }}';
const CREDENTIAL_DIR = '${HOME}/.config/dart';
const CREDENTIAL_PATH = `${CREDENTIAL_DIR}/pub-credentials.json`;
const CREDENTIAL_FILE = 'pub-credentials.json';

const TAG_VALUE = '${{ inputs.tag }}';
const SETUP_NIX = 'AtomiCloud/actions.setup-nix@v3';
const WORKFLOW_NAME = '⚡ Reusable Dart Publish';
const JOB_NAME = 'Publish to pub.dev';
const TIMEOUT_MINUTES = 20;
const RUNNER_LABELS = [
  'nscloud-ubuntu-22.04-amd64-4x8-with-cache',
  'nscloud-cache-size-50gb',
  'nscloud-cache-tag-atomi-nix-store-cache-linux-amd64',
];

// A `echo "…" >&2` diagnostic. The message is free text — rewording a failure
// message is not a policy change — but nothing else may share the line.
const DIAGNOSTIC = /^echo "[^"]*" >&2$/;

// The exact approved scripts, as ordered command lists.
const TAG_PIN_SCRIPT: Array<string | RegExp> = [
  '[[ ${TAG} =~ ^v[0-9]+[.][0-9]+[.][0-9]+([+-][0-9A-Za-z.-]+)?$ ]] || {',
  DIAGNOSTIC,
  'exit 1',
  '}',
  'git fetch --tags --force origin',
  'git checkout "refs/tags/${TAG}" -- packages/diene_config',
  'git --no-pager diff --stat "refs/tags/${TAG}" -- packages/diene_config',
];
const CONFIGURE_SCRIPT: Array<string | RegExp> = [
  `mkdir -p "${CREDENTIAL_DIR}"`,
  `printf '%s' "\${${CREDENTIAL_KEY}}" > "${CREDENTIAL_PATH}"`,
  `chmod 600 "${CREDENTIAL_PATH}"`,
  `[ -s "${CREDENTIAL_PATH}" ] || {`,
  DIAGNOSTIC,
  'exit 1',
  '}',
];
const VERIFY_SCRIPT: Array<string | RegExp> = ['nix develop .#cd -c ./scripts/ci/publish.sh "${TAG}"'];
const CLEANUP_SCRIPT: Array<string | RegExp> = [`rm -f "${CREDENTIAL_PATH}"`];

interface StepSpec {
  label: string;
  keys: string[];
  uses?: string;
  name?: string;
  env?: Record<string, string>;
  ifCond?: string;
  script?: Array<string | RegExp>;
}

// The complete expected job body. Because each entry pins its own key set, no
// execution modifier can be attached to any step: `continue-on-error`, `if` on a
// step that should not have one, `shell`, `working-directory`, `with`, `timeout-
// minutes`, or an extra `env` var are all rejected by the key set alone. Because
// the list length is fixed, no step can be inserted while the credential exists.
const EXPECTED_STEPS: StepSpec[] = [
  { label: 'pinned setup-nix action', keys: ['uses'], uses: SETUP_NIX },
  {
    label: 'tag pin',
    keys: ['name', 'env', 'run'],
    name: 'Pin the published member to the release tag',
    env: { TAG: TAG_VALUE },
    script: TAG_PIN_SCRIPT,
  },
  {
    label: 'configure credentials',
    keys: ['name', 'env', 'run'],
    name: 'Configure pub.dev credentials',
    env: { [CREDENTIAL_KEY]: CREDENTIAL_VALUE },
    script: CONFIGURE_SCRIPT,
  },
  {
    label: 'verify and publish',
    keys: ['name', 'env', 'run'],
    name: 'Verify manifest==tag and publish',
    env: { TAG: TAG_VALUE },
    script: VERIFY_SCRIPT,
  },
  {
    label: 'always cleanup',
    keys: ['name', 'if', 'run'],
    name: 'Remove pub.dev credentials',
    ifCond: 'always()',
    script: CLEANUP_SCRIPT,
  },
];

const CONFIGURE_INDEX = EXPECTED_STEPS.findIndex(step => step.env?.[CREDENTIAL_KEY] === CREDENTIAL_VALUE);
const CLEANUP_INDEX = EXPECTED_STEPS.findIndex(step => step.script === CLEANUP_SCRIPT);

// Exactly the keys the workflow and its job may carry. Anything absent from
// these lists is rejected, which is what forbids workflow- or job-level `env`
// (so `HOME`, `BASH_ENV`, and `PATH` cannot be redirected), `defaults` (so no
// custom shell or working directory), and job-level `continue-on-error`.
const WORKFLOW_KEYS = ['name', 'on', 'jobs'];
const JOB_KEYS = ['name', 'permissions', 'environment', 'timeout-minutes', 'runs-on', 'steps'];
const JOB_PERMISSIONS = { contents: 'read' };

// The only accepted trigger: a reusable call taking exactly one required string
// input. Pinning this exactly is what forbids an extra `secrets:` block (a second
// credential channel), an extra input, or a relaxed `required: false`.
const TAG_INPUT_KEYS = ['description', 'required', 'type'];

interface Occurrence {
  path: string;
  text: string;
}

function isMapping(node: unknown): node is Record<string, unknown> {
  return typeof node === 'object' && node !== null && !Array.isArray(node);
}

function hasExactKeys(node: unknown, keys: string[]): boolean {
  if (!isMapping(node)) return false;
  const actual = Object.keys(node);
  if (actual.length !== keys.length) return false;
  const expected = [...keys].sort();
  return [...actual].sort().every((key, index) => key === expected[index]);
}

function mappingEquals(node: unknown, expected: Record<string, string>): boolean {
  if (!hasExactKeys(node, Object.keys(expected))) return false;
  const actual = node as Record<string, unknown>;
  return Object.entries(expected).every(([key, value]) => actual[key] === value);
}

// Every scalar and every mapping key in the parsed document, with its path.
// A backstop for the free-text fields the specs above deliberately leave open
// (job name, trigger description, diagnostic messages): the credential name and
// its filename must still appear only where the policy allows.
function collectOccurrences(node: unknown, path: string, sink: Occurrence[]): void {
  if (typeof node === 'string') {
    sink.push({ path, text: node });
    return;
  }
  if (Array.isArray(node)) {
    node.forEach((item, index) => collectOccurrences(item, `${path}[${index}]`, sink));
    return;
  }
  if (!isMapping(node)) return;
  for (const [key, value] of Object.entries(node)) {
    sink.push({ path: `${path}.${key}`, text: key });
    collectOccurrences(value, `${path}.${key}`, sink);
  }
}

// A `run:` script as an ordered command list. Blank lines carry no meaning to the
// shell and are dropped; comments are NOT dropped, because a commented-out
// `rm -f` is precisely the no-op cleanup this gate has to reject.
function commandList(run: unknown): string[] {
  if (typeof run !== 'string') return [];
  return run
    .split('\n')
    .map(line => line.trim())
    .filter(line => line !== '');
}

function scriptMatches(run: unknown, expected: Array<string | RegExp>): boolean {
  const commands = commandList(run);
  if (commands.length !== expected.length) return false;
  return expected.every((matcher, index) =>
    typeof matcher === 'string' ? commands[index] === matcher : matcher.test(commands[index]),
  );
}

function stepMatches(step: unknown, spec: StepSpec): boolean {
  if (!hasExactKeys(step, spec.keys)) return false;
  const actual = step as Record<string, unknown>;
  if (spec.uses !== undefined && actual.uses !== spec.uses) return false;
  if (spec.name !== undefined && actual.name !== spec.name) return false;
  if (spec.ifCond !== undefined && actual.if !== spec.ifCond) return false;
  if (spec.env !== undefined && !mappingEquals(actual.env, spec.env)) return false;
  if (spec.script !== undefined && !scriptMatches(actual.run, spec.script)) return false;
  return true;
}

// GitHub resolves `permissions: write-all` to write access for every available
// permission — including `id-token: write`, which is all trusted publishing
// needs. The job's permissions must therefore be exactly `contents: read`: a
// scalar shorthand is not a mapping and is rejected, and no `id-token` key in any
// quoting or flow syntax can survive an exact mapping comparison (the parser has
// already normalized `"id-token"`, `id-token: "write"`, and `{id-token: write}`
// to the same key).
function permissionsAreSafe(permissions: unknown): boolean {
  if (!mappingEquals(permissions, JOB_PERMISSIONS)) return false;
  return !Object.keys(permissions as Record<string, unknown>).some(key => key.trim().toLowerCase() === 'id-token');
}

// The live workflow spells the environment as a scalar, so that is the only
// accepted form: an equivalent-looking `{name: pub.dev}` mapping is still a
// deviation from the certified shape, and this gate certifies one exact shape.
function environmentIsPinned(environment: unknown): boolean {
  return environment === DEPLOY_ENVIRONMENT;
}

// Exactly one required string input named `tag`, and no `secrets:` block.
function triggerIsExact(on: unknown): boolean {
  if (!hasExactKeys(on, ['workflow_call'])) return false;
  const call = (on as Record<string, unknown>).workflow_call;
  if (!hasExactKeys(call, ['inputs'])) return false;
  const inputs = (call as Record<string, unknown>).inputs;
  if (!hasExactKeys(inputs, ['tag'])) return false;
  const tag = (inputs as Record<string, unknown>).tag;
  if (!hasExactKeys(tag, TAG_INPUT_KEYS)) return false;
  const spec = tag as Record<string, unknown>;
  if (spec.required !== true || spec.type !== 'string') return false;
  return typeof spec.description === 'string';
}

function credentialPolicyHolds(source: string): boolean {
  let document: unknown;
  try {
    document = Bun.YAML.parse(source);
  } catch {
    return false;
  }

  // 1. the workflow carries exactly these top-level keys — no workflow-level
  //    `env` (HOME/BASH_ENV/PATH), no `defaults` (shell, working directory), no
  //    workflow-level `permissions` shorthand
  if (!hasExactKeys(document, WORKFLOW_KEYS)) return false;
  const doc = document as Record<string, unknown>;
  if (doc.name !== WORKFLOW_NAME) return false;

  // 2. reusable-call is the only way in — no push/pull_request trigger can put
  //    this credentialed job on an untrusted ref — and the call surface is
  //    exactly one required string `tag` with no extra inputs and no `secrets:`
  if (!triggerIsExact(doc.on)) return false;

  // 3. exactly one job, and it is `publish`. A second job is how cleanup gets
  //    moved off this runner and how a `pub.dev` decoy satisfies a workflow-wide
  //    environment search.
  if (!hasExactKeys(doc.jobs, [PUBLISH_JOB])) return false;
  const publish = (doc.jobs as Record<string, unknown>)[PUBLISH_JOB];

  // 4. the job carries exactly these keys — this is what makes job-level `env`
  //    (and so a `HOME` override that relocates the credential), `defaults`,
  //    `continue-on-error`, `strategy`, `container`, and `services` impossible
  if (!hasExactKeys(publish, JOB_KEYS)) return false;
  const job = publish as Record<string, unknown>;

  // 5. the job's own deployment environment is pinned, its permissions are
  //    exactly `contents: read`, it runs on the approved runner set, and its
  //    credential window is bounded to the approved timeout
  if (job.name !== JOB_NAME) return false;
  if (!environmentIsPinned(job.environment)) return false;
  if (!permissionsAreSafe(job.permissions)) return false;
  if (!Array.isArray(job['runs-on'])) return false;
  const labels = job['runs-on'] as unknown[];
  if (labels.length !== RUNNER_LABELS.length) return false;
  if (!labels.every((label, index) => label === RUNNER_LABELS[index])) return false;
  if (job['timeout-minutes'] !== TIMEOUT_MINUTES) return false;

  // 6. exactly the approved steps, in order, each an exact key set with an exact
  //    env mapping and an exact command sequence. No step may be inserted while
  //    the credential exists, and no step may carry an execution modifier.
  if (!Array.isArray(job.steps)) return false;
  const steps = job.steps as unknown[];
  if (steps.length !== EXPECTED_STEPS.length) return false;
  if (!steps.every((step, index) => stepMatches(step, EXPECTED_STEPS[index]))) return false;

  const occurrences: Occurrence[] = [];
  collectOccurrences(document, '', occurrences);
  const configurePath = `.jobs.${PUBLISH_JOB}.steps[${CONFIGURE_INDEX}]`;
  const cleanupPath = `.jobs.${PUBLISH_JOB}.steps[${CLEANUP_INDEX}]`;

  // 7. backstop over the free-text fields: the credential name appears only
  //    where it is injected and written, its filename only in the approved write
  //    and removal, and the workflow consumes exactly one secret
  const credentialPaths = [`${configurePath}.env.${CREDENTIAL_KEY}`, `${configurePath}.run`];
  const filePaths = [`${configurePath}.run`, `${cleanupPath}.run`];
  for (const { path, text } of occurrences) {
    if (text.includes(CREDENTIAL_KEY) && !credentialPaths.includes(path)) return false;
    if (text.includes(CREDENTIAL_FILE) && !filePaths.includes(path)) return false;
  }
  const secretRefs = occurrences.filter(({ text }) => /\$\{\{[^}]*\bsecrets\./.test(text));
  if (secretRefs.length !== 1) return false;
  if (secretRefs[0].path !== `${configurePath}.env.${CREDENTIAL_KEY}`) return false;

  return true;
}

const PERMISSIONS_BLOCK = '    permissions:\n      contents: read\n';
const CONFIGURE_ENV = `        env:\n          ${CREDENTIAL_KEY}: ${CREDENTIAL_VALUE}\n`;
const CONFIGURE_HEADER = '      - name: Configure pub.dev credentials\n';
const VERIFY_HEADER = '      - name: Verify manifest==tag and publish\n';
const CLEANUP_STEP =
  `      - name: Remove pub.dev credentials\n` + `        if: always()\n` + `        run: rm -f "${CREDENTIAL_PATH}"\n`;
const LOCKDOWN_LINE = `          chmod 600 "${CREDENTIAL_PATH}"\n`;
const DECOY_JOB =
  `  decoy:\n` +
  `    runs-on: ubuntu-latest\n` +
  `    steps:\n` +
  `      - name: Decoy\n` +
  `        run: echo decoy\n`;

// Add a command to the credential-configuring step, immediately after chmod.
function injectIntoConfigure(source: string, command: string): string {
  return source.replace(LOCKDOWN_LINE, `${LOCKDOWN_LINE}          ${command}\n`);
}

// Insert a whole step immediately after the credential is materialized — i.e.
// inside the window where the credential file exists on disk.
function insertAfterConfigure(source: string, step: string): string {
  return source.replace(VERIFY_HEADER, `${step}${VERIFY_HEADER}`);
}

// Replace the `[ -s … ] || { … }` guard without hardcoding its message.
function replaceNonEmptyGuard(source: string, replacement: string): string {
  const lines = source.split('\n');
  const start = lines.findIndex(line => line.trim().startsWith('[ -s '));
  if (start === -1) return source;
  let end = start;
  while (end < lines.length && lines[end].trim() !== '}') end += 1;
  const indent = ' '.repeat(lines[start].length - lines[start].trimStart().length);
  lines.splice(start, end - start + 1, ...(replacement === '' ? [] : [`${indent}${replacement}`]));
  return lines.join('\n');
}

// In-memory negative controls. Each builder must produce a workflow the policy
// REJECTS; together they prove no limb of the predicate is vacuous. Every one is
// valid Actions YAML, and each was accepted by some earlier version of this
// predicate — these are regressions that really happened, not hypotheticals.
const BYPASSES: Array<{ label: string; build: (source: string) => string }> = [
  // --- arbitrary execution inside the credential window -------------------
  {
    label: 'credential directory exfiltrated by glob, never naming the file',
    build: source =>
      insertAfterConfigure(source, '      - name: Collect diagnostics\n        run: base64 "$HOME/.config/dart/"*\n'),
  },
  {
    label: 'rogue dart pub publish spends the credential outside the approved entrypoint',
    build: source =>
      insertAfterConfigure(
        source,
        '      - name: Extra publish\n        run: cd packages/diene_config && dart pub publish --force\n',
      ),
  },
  {
    label: 'benign-looking extra step executes while the credential exists',
    build: source => insertAfterConfigure(source, '      - name: Unrelated\n        run: echo hello\n'),
  },
  // --- control flow that neutralizes the guard ---------------------------
  {
    label: 'continue-on-error on Configure (an empty-credential failure no longer blocks publish)',
    build: source => source.replace(CONFIGURE_ENV, `        continue-on-error: true\n${CONFIGURE_ENV}`),
  },
  {
    label: 'if: always() on Verify (publishes even after Configure fails)',
    build: source => source.replace(VERIFY_HEADER, `${VERIFY_HEADER}        if: always()\n`),
  },
  // --- relocating or reinterpreting the credential -----------------------
  {
    label: 'job-level HOME override relocates the supposedly canonical credential path',
    build: source =>
      source.replace(
        `    environment: ${DEPLOY_ENVIRONMENT}\n`,
        `    environment: ${DEPLOY_ENVIRONMENT}\n    env:\n      HOME: /tmp\n`,
      ),
  },
  {
    label: 'workflow-level defaults impose a custom shell on every run step',
    build: source => source.replace('jobs:\n', 'defaults:\n  run:\n    shell: bash -x {0}\n\njobs:\n'),
  },
  {
    label: 'custom shell on the Configure step',
    build: source => source.replace(CONFIGURE_ENV, `        shell: bash -x {0}\n${CONFIGURE_ENV}`),
  },
  {
    label: 'working-directory override on the Configure step',
    build: source => source.replace(CONFIGURE_ENV, `        working-directory: /tmp\n${CONFIGURE_ENV}`),
  },
  {
    label: 'BASH_ENV injected into the Verify step',
    build: source =>
      source.replace(
        '          TAG: ${{ inputs.tag }}\n        run: nix develop',
        '          TAG: ${{ inputs.tag }}\n          BASH_ENV: /tmp/evil.sh\n        run: nix develop',
      ),
  },
  {
    label: 'runner swapped to an unapproved label',
    build: source => source.replace('      - nscloud-cache-size-50gb\n', '      - self-hosted-attacker\n'),
  },
  {
    label: 'pull_request trigger added so the credentialed job runs on untrusted refs',
    build: source => source.replace('on:\n  workflow_call:\n', 'on:\n  pull_request:\n  workflow_call:\n'),
  },
  {
    label: 'a workflow_call secrets block opens a second credential channel',
    build: source =>
      source.replace(
        '  workflow_call:\n    inputs:\n',
        '  workflow_call:\n    secrets:\n      PUB_CREDENTIALS_JSON:\n        required: true\n      EXTRA:\n        required: false\n    inputs:\n',
      ),
  },
  {
    label: 'an extra workflow_call input widens the call surface',
    build: source =>
      source.replace(
        '    inputs:\n      tag:\n',
        '    inputs:\n      channel:\n        required: false\n        type: string\n      tag:\n',
      ),
  },
  {
    label: 'the tag input relaxed to required: false',
    build: source => source.replace('        required: true\n', '        required: false\n'),
  },
  {
    label: 'the credential window widened by a long timeout',
    build: source => source.replace(`    timeout-minutes: ${TIMEOUT_MINUTES}\n`, '    timeout-minutes: 360\n'),
  },
  {
    label: 'the timeout removed so the credential window is unbounded',
    build: source => source.replace(`    timeout-minutes: ${TIMEOUT_MINUTES}\n`, ''),
  },
  {
    label: 'setup-nix action unpinned from its major version',
    build: source => source.replace(`uses: ${SETUP_NIX}`, 'uses: AtomiCloud/actions.setup-nix@main'),
  },
  // --- credential scope -------------------------------------------------
  {
    label: 'credential hoisted from the step to job-level env (exposed to every step)',
    build: source =>
      source
        .replace(CONFIGURE_ENV, '')
        .replace(
          `    environment: ${DEPLOY_ENVIRONMENT}\n`,
          `    environment: ${DEPLOY_ENVIRONMENT}\n    env:\n      ${CREDENTIAL_KEY}: ${CREDENTIAL_VALUE}\n`,
        ),
  },
  {
    label: 'a second secret pulled into the same step',
    build: source =>
      source.replace(
        `        env:\n          ${CREDENTIAL_KEY}:`,
        `        env:\n          OTHER: \${{ secrets.OTHER }}\n          ${CREDENTIAL_KEY}:`,
      ),
  },
  {
    label: 'credential echoed to the log',
    build: source => injectIntoConfigure(source, `echo "\${${CREDENTIAL_KEY}}"`),
  },
  {
    label: 'credential file read into the log with cat',
    build: source => injectIntoConfigure(source, `cat "${CREDENTIAL_PATH}"`),
  },
  {
    label: 'credential copied to a noncanonical path with cp',
    build: source => injectIntoConfigure(source, `cp "${CREDENTIAL_PATH}" /tmp/creds`),
  },
  {
    label: 'step env exported to GITHUB_ENV (leaks the secret to every later step)',
    build: source => injectIntoConfigure(source, 'env >> "$GITHUB_ENV"'),
  },
  {
    label: 'credential written outside the canonical HOME path',
    build: source => source.split(CREDENTIAL_PATH).join('./pub-credentials.json'),
  },
  // --- OIDC, in every syntax that parses to an id-token key --------------
  {
    label: 'OIDC re-requested with a plain id-token key',
    build: source => source.replace('      contents: read', '      id-token: write\n      contents: read'),
  },
  {
    label: 'OIDC re-requested with a quoted id-token value',
    build: source => source.replace('      contents: read', '      id-token: "write"\n      contents: read'),
  },
  {
    label: 'OIDC re-requested with a quoted id-token key',
    build: source => source.replace('      contents: read', '      "id-token": write\n      contents: read'),
  },
  {
    label: 'OIDC re-requested through an inline flow mapping',
    build: source => source.replace(PERMISSIONS_BLOCK, '    permissions: { contents: read, "id-token": "write" }\n'),
  },
  {
    label: 'OIDC re-requested through an unquoted inline flow mapping',
    build: source => source.replace(PERMISSIONS_BLOCK, '    permissions: { contents: read, id-token: write }\n'),
  },
  {
    label: 'job permissions replaced by the write-all shorthand (grants id-token without naming it)',
    build: source => source.replace(PERMISSIONS_BLOCK, '    permissions: write-all\n'),
  },
  {
    label: 'job permissions replaced by a quoted write-all shorthand',
    build: source => source.replace(PERMISSIONS_BLOCK, '    permissions: "write-all"\n'),
  },
  {
    label: 'workflow-level write-all inherited by a second job',
    build: source => source.replace('jobs:\n', `permissions: write-all\n\njobs:\n${DECOY_JOB}`),
  },
  // --- the guard and the cleanup ----------------------------------------
  {
    label: 'non-empty guard deleted (an empty secret reaches dart pub)',
    build: source => replaceNonEmptyGuard(source, ''),
  },
  {
    label: 'non-empty guard short-circuited with || true (an empty secret still reaches dart pub)',
    build: source => replaceNonEmptyGuard(source, `[ -s "${CREDENTIAL_PATH}" ] || true`),
  },
  {
    label: 'chmod 600 dropped',
    build: source => source.replace(LOCKDOWN_LINE, ''),
  },
  {
    label: 'chmod 600 commented out into a no-op',
    build: source => source.replace(LOCKDOWN_LINE, `          # chmod 600 "${CREDENTIAL_PATH}"\n`),
  },
  {
    label: 'cleanup step loses if: always() (skipped when publish fails)',
    build: source => source.replace('        if: always()\n', ''),
  },
  {
    label: 'cleanup step removed entirely',
    build: source => source.replace(CLEANUP_STEP, ''),
  },
  {
    label: 'cleanup short-circuited so it never runs',
    build: source =>
      source.replace(`        run: rm -f "${CREDENTIAL_PATH}"`, `        run: false && rm -f "${CREDENTIAL_PATH}"`),
  },
  {
    label: 'cleanup commented out into a no-op',
    build: source =>
      source.replace(
        `        run: rm -f "${CREDENTIAL_PATH}"`,
        `        run: |\n          # rm -f "${CREDENTIAL_PATH}"\n          true`,
      ),
  },
  {
    label: 'cleanup moved to a separate job that cannot clean the publish runner',
    build: source => source.replace(CLEANUP_STEP, '').replace('jobs:\n', `jobs:\n${DECOY_JOB}${CLEANUP_STEP}`),
  },
  {
    label: 'cleanup reordered before the publish step',
    build: source => source.replace(CLEANUP_STEP, '').replace(VERIFY_HEADER, `${CLEANUP_STEP}${VERIFY_HEADER}`),
  },
  // --- the publish entrypoint and the tag pin ---------------------------
  {
    label: 'publish entrypoint replaced so the credential is used by something else',
    build: source => source.replace('./scripts/ci/publish.sh "${TAG}"', './scripts/ci/rogue.sh "${TAG}"'),
  },
  {
    label: 'tag validation guard removed from the pin step',
    build: source =>
      source.replace(
        /      - name: Pin the published member to the release tag\n(?:.*\n)*?          git fetch/,
        '      - name: Pin the published member to the release tag\n        env:\n          TAG: ${{ inputs.tag }}\n        run: |\n          git fetch',
      ),
  },
  {
    label: 'tag pin no longer restores the package from the tag',
    build: source => source.replace('git checkout "refs/tags/${TAG}" -- packages/diene_config\n', ''),
  },
  // --- the deployment environment ---------------------------------------
  {
    label: 'pub.dev deployment environment unpinned',
    build: source => source.replace(`    environment: ${DEPLOY_ENVIRONMENT}\n`, ''),
  },
  {
    label: 'publish job unpinned to staging while a decoy job holds the pub.dev environment',
    build: source =>
      source
        .replace(`    environment: ${DEPLOY_ENVIRONMENT}\n`, '    environment: staging\n')
        .replace('jobs:\n', `jobs:\n${DECOY_JOB}    environment: ${DEPLOY_ENVIRONMENT}\n`),
  },
];

export default {
  contractVersion: 1,
  sandbox: { snapshot: 'git' },
  probes: [
    {
      name: 'baseline-automated-publishing-credential-policy-green',
      description:
        'the publish workflow is exactly the approved shape: one reusable-call trigger, one pub.dev-pinned publish job with contents:read only, and exactly the five approved steps in order, so the org credential is written 0600 under HOME, proven non-empty, spent only by the approved entrypoint, and always removed',
      kind: 'baseline',
      async run(repo: any) {
        if (!credentialPolicyHolds(await repo.read(REUSABLE_PUBLISH))) {
          throw new Error(
            'automated-publishing-credential-policy: publish workflow violates the credentialed publish policy',
          );
        }
      },
    },
    {
      name: 'mutation-automated-publishing-credential-policy-caught',
      description:
        'the policy check detects any deviation from the approved publish shape: an extra step inside the credential window, exfiltration by directory glob, a rogue publish, continue-on-error or if: always() defeating the guard, a HOME or shell override, OIDC in any permissions syntax, and every form of dropped, hoisted, leaked, or no-op credential handling',
      kind: 'mutation',
      expectedImpact: [],
      async run(repo: any) {
        const source = await repo.read(REUSABLE_PUBLISH);
        if (!credentialPolicyHolds(source)) {
          throw new Error('automated-publishing-credential-policy: policy already broken before sabotage');
        }

        // Every bypass must be rejected. These run in memory so one probe row
        // covers the whole boundary without adding inventory rows.
        for (const { label, build } of BYPASSES) {
          const mutated = build(source);
          if (mutated === source) {
            throw new Error(`automated-publishing-credential-policy: negative control did not apply: ${label}`);
          }
          if (credentialPolicyHolds(mutated)) {
            throw new Error(`automated-publishing-credential-policy: policy survived sabotage: ${label}`);
          }
        }

        await repo.write(REUSABLE_PUBLISH, source.split(CREDENTIAL_VALUE).join("''"));
        if (credentialPolicyHolds(await repo.read(REUSABLE_PUBLISH))) {
          throw new Error('automated-publishing-credential-policy: policy survived sabotage');
        }
      },
    },
  ],
};
