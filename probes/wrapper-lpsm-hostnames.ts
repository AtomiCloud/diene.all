import { defineSmoke } from './lib/definition.ts';
import { shellQuote } from './lib/exec.ts';
import { withCleanProbeState } from './lib/helpers.ts';

// Every scalar below is authorized-assembler output that this chart only ever
// verifies. `DIGEST` is the SHA-256 of the canonical manifest bytes committed in
// `chart/values.yaml`, `LEASE_KEY` is `"p" || base32hex-lowercase(first 16 bytes)`
// of that digest, and `SUFFIX` is therefore the first three base32hex digest
// characters. `OTHER_DIGEST` is a second, DIFFERENT manifest's digest: the live
// allocation a base-petname collision is recorded against.
const DIGEST = '7527f8ce8af22ee78eaaeaa68d24857bf88c3c5a8a9d2fd812f607441cfbca7d';
const OTHER_DIGEST = '8cd31a396907eae9357fd730e605e0a8e8f6fb82dddcfc57819f44c00c9f1531';
const COMMIT = 'e8266aaad16351c0a8695370b6d4d79d7d744ed2';
// gitleaks:allow — a deterministic, public example lease key, never a credential.
const LEASE_KEY = 'p00000000000000000000000000'; // gitleaks:allow
const SUFFIX = LEASE_KEY.slice(1, 4);
const PETNAME = 'otter-beats-potato';
const SUFFIXED = `${PETNAME}-${SUFFIX}`;
const PREVIEW_ZONE = 'kube.entei.dev.atomi.cloud';

const PREVIEW = ['--set instance.preview.enabled=true', `--set-string contracts.lpsm.instanceZone=${PREVIEW_ZONE}`];

// A mint that had to disambiguate: the same base petname was already held live by
// an allocation with a DIFFERENT full digest.
const COLLIDED = [
  ...PREVIEW,
  `--set-string instance.preview.canonical.previewPetname=${SUFFIXED}`,
  `--set-string instance.preview.receipt.previewPetname=${SUFFIXED}`,
  `--set-string instance.preview.receipt.collision.liveFullLeaseDigest=${OTHER_DIGEST}`,
];

const pin = (key: string, value: string) => `--set-string 'instance.preview.manifest.pins.${key}=${value}'`;
const resolution = (key: string, field: string, value: string) =>
  `--set-string 'instance.preview.manifest.branchResolutions.${key}.${field}=${value}'`;

type Accepts = { name: string; flags: string[]; key: string; expected: string };
type Refuses = { name: string; flags: string[]; because: string[] };
type Stable = { name: string; key: string; left: string[]; right: string[] };

// Proven values. The ordinary form, the optional-instance projection, the
// namespace-sourced platform slot, the separate-instance parse, and the recorded
// original/label pair all survive the preview boundary unchanged.
const ACCEPTS: Accepts[] = [
  {
    name: 'ordinary-dotted-form',
    flags: [],
    key: 'lpsm.ordinaryHostname',
    expected: 'api.wrapper.sample.example.cluster.atomi.cloud',
  },
  {
    name: 'optional-instance-dotted-form',
    flags: [],
    key: 'lpsm.instanceHostname',
    expected: 'api.wrapper.sample.run001.example.local.example.invalid',
  },
  {
    name: 'parser-returns-instance-separately',
    flags: [],
    key: 'lpsm.parsed',
    expected: '{"instance":"run001","landscape":"example","module":"api","platform":"sample","service":"wrapper"}',
  },
  {
    name: 'non-preview-original-recorded-verbatim',
    flags: [],
    key: 'instance.original',
    expected: 'example-repository-run-001',
  },
  {
    name: 'non-preview-label-is-the-same-bytes',
    flags: [],
    key: 'instance.label',
    expected: 'example-repository-run-001',
  },
  { name: 'versioned-noun-verb-noun-petname', flags: PREVIEW, key: 'preview.petname', expected: PETNAME },
  {
    name: 'versioned-word-list-recorded',
    flags: PREVIEW,
    key: 'preview.wordList',
    expected: 'diene.preview-wordlist/v1',
  },
  {
    name: 'preview-coordinate-uses-the-petname',
    flags: PREVIEW,
    key: 'preview.hostname',
    expected: `api.wrapper.sample.${PETNAME}.castform.${PREVIEW_ZONE}`,
  },
  { name: 'preview-original-is-the-petname', flags: PREVIEW, key: 'instance.original', expected: PETNAME },
  { name: 'preview-label-is-the-same-bytes', flags: PREVIEW, key: 'instance.label', expected: PETNAME },
  {
    name: 'live-collision-adds-exactly-three-base32hex-characters',
    flags: COLLIDED,
    key: 'preview.hostname',
    expected: `api.wrapper.sample.${SUFFIXED}.castform.${PREVIEW_ZONE}`,
  },
];

// Refusals. Each asserts the reason, not merely a non-zero exit, so a vector
// cannot pass because an unrelated render error happened to fire.
const REFUSES: Refuses[] = [
  {
    name: 'mint-time-name-is-immutable',
    flags: [...COLLIDED, `--set-string instance.preview.canonical.previewPetname=${PETNAME}`],
    because: ['recorded at mint'],
  },
  {
    name: 'full-digest-mismatch',
    flags: [...PREVIEW, `--set-string instance.preview.canonical.fullLeaseDigest=${OTHER_DIGEST}`],
    because: ['does not equal the receipt digest'],
  },
  {
    name: 'suffix-without-a-recorded-collision',
    flags: [
      ...PREVIEW,
      `--set-string instance.preview.canonical.previewPetname=${SUFFIXED}`,
      `--set-string instance.preview.receipt.previewPetname=${SUFFIXED}`,
    ],
    because: ['carries a collision suffix with no recorded live base-petname collision'],
  },
  {
    name: 'caller-supplied-suffix',
    flags: [
      ...PREVIEW,
      `--set-string instance.preview.canonical.previewPetname=${PETNAME}-abc`,
      `--set-string instance.preview.receipt.previewPetname=${PETNAME}-abc`,
      `--set-string instance.preview.receipt.collision.liveFullLeaseDigest=${OTHER_DIGEST}`,
    ],
    because: ['is not the first three base32hex digest characters'],
  },
  {
    name: 'suffix-longer-than-three-characters',
    flags: [
      ...PREVIEW,
      `--set-string instance.preview.canonical.previewPetname=${SUFFIXED}9`,
      `--set-string instance.preview.receipt.previewPetname=${SUFFIXED}9`,
      `--set-string instance.preview.receipt.collision.liveFullLeaseDigest=${OTHER_DIGEST}`,
    ],
    because: ['is not a versioned NOUN-VERB-NOUN petname', `'${SUFFIXED}9' does not match pattern`],
  },
  {
    name: 'same-digest-is-not-a-collision',
    flags: [...COLLIDED, `--set-string instance.preview.receipt.collision.liveFullLeaseDigest=${DIGEST}`],
    because: ['idempotent join, never a petname collision'],
  },
  {
    name: 'recorded-collision-must-show-in-the-name',
    flags: [...PREVIEW, `--set-string instance.preview.receipt.collision.liveFullLeaseDigest=${OTHER_DIGEST}`],
    because: ['carries no collision suffix'],
  },
  {
    name: 'unsigned-receipt',
    flags: [...PREVIEW, '--set-string instance.preview.receipt.signature='],
    because: ['the assembler receipt is missing'],
  },
  {
    name: 'unversioned-word-list',
    flags: [...PREVIEW, '--set-string instance.preview.receipt.wordList=diene.preview-wordlist'],
    because: ['is not a versioned diene.preview-wordlist', "at '/instance/preview/receipt/wordList'"],
  },
  {
    name: 'petname-outside-the-grammar',
    flags: [
      ...PREVIEW,
      '--set-string instance.preview.canonical.previewPetname=otterbeatspotato',
      '--set-string instance.preview.receipt.previewPetname=otterbeatspotato',
    ],
    because: ['is not a versioned NOUN-VERB-NOUN petname', "'otterbeatspotato' does not match pattern"],
  },
  {
    name: 'fork-source-outside-the-ruled-pair',
    flags: [...PREVIEW, '--set-string instance.preview.receipt.forkSource=serving'],
    because: ['is neither staging nor production', "at '/instance/preview/receipt/forkSource'"],
  },
  {
    name: 'unresolved-branch-pin',
    flags: [...PREVIEW, pin('nitroso\\.zinc', 'main')],
    because: ['must be resolved to its commit at mint'],
  },
  {
    name: 'branch-moved-past-its-mint-commit',
    flags: [...PREVIEW, resolution('nitroso\\.zinc', 'commit', '0'.repeat(40))],
    because: ['never follows its branch past mint'],
  },
  {
    name: 'module-keyed-pin',
    flags: [...PREVIEW, pin('nitroso\\.zinc\\.api', '1.0.0')],
    because: ['with no module segment'],
  },
  {
    name: 'ref-bearing-pin',
    flags: [...PREVIEW, `--set-string 'instance.preview.manifest.pins.auth\\.logto.ref=refs/heads/main'`],
    because: ['must carry exactly kind and version'],
  },
  {
    name: 'unnormalized-physical-id',
    flags: ['--set-string instance.original=repository-a:pr-123'],
    because: ['never normalizes it', "'repository-a:pr-123' does not match pattern"],
  },
  {
    name: 'overlong-physical-id',
    flags: [`--set-string instance.original=repository-${'0'.repeat(70)}1`],
    because: ['shorten it at the authorized minter', 'maxLength: got 82, want 63'],
  },
  {
    name: 'dash-fused-garden-hostname',
    flags: ['--set-string contracts.lpsm.parseHostname=api-wrapper-sample-run001-example.local.example.invalid'],
    because: ['must use the canonical dotted LPSM form'],
  },
  {
    name: 'uppercase-parser-input',
    flags: ['--set-string contracts.lpsm.parseHostname=API.wrapper.sample.run001.example.local.example.invalid'],
    because: ['must be a lowercase DNS-1123 label'],
  },
  {
    name: 'platform-slot-from-a-values-file',
    flags: ['--set-string serviceTree.platform=other'],
    because: ['must equal release namespace'],
  },
];

// A branch that moved (or was renamed) after mint cannot move the rendered
// hostname: nothing outward is recomputed from the manifest.
const STABLE: Stable[] = [
  {
    name: 'branch-pin-hostname-stability',
    key: 'preview.hostname',
    left: [...COLLIDED, resolution('nitroso\\.zinc', 'commit', COMMIT)],
    right: [...COLLIDED, resolution('nitroso\\.zinc', 'branch', 'release/2026-08')],
  },
];

function renderCommand(flags: string[]): string {
  return ['helm template helm-wrapper chart --namespace sample --values chart/values.example.yaml', ...flags].join(' ');
}

function readCommand(flags: string[], key: string): string {
  const selector = `select(.kind == "ConfigMap" and .metadata.name == "wrapper-contracts") | .data."${key}"`;
  return `${renderCommand(flags)} | yq -r '${selector}'`;
}

function vectorScript(): string {
  const lines = [
    '#!/usr/bin/env bash',
    'set -uo pipefail',
    '',
    'bash ./scripts/local/vendor-chart-config.sh >/dev/null',
    'fail=0',
    '',
  ];

  for (const vector of ACCEPTS) {
    lines.push(
      `want=${shellQuote(vector.expected)}`,
      `got="$(${readCommand(vector.flags, vector.key)} 2>&1)"`,
      'if [ "$got" != "$want" ]; then',
      `  printf '%s\\n' "❌ ${vector.name}: expected $want" >&2`,
      `  printf '%s\\n' "   got: $got" >&2`,
      '  fail=1',
      'fi',
      '',
    );
  }

  for (const vector of REFUSES) {
    // Either boundary may own the refusal: the generated values schema rejects a
    // malformed shape before rendering, the template helper rejects an
    // inconsistent-but-well-shaped receipt. Both are named, so a vector still
    // cannot pass on an unrelated failure.
    const reasons = vector.because.map(reason => `printf '%s' "$out" | grep -qF ${shellQuote(reason)}`).join(' || ');
    lines.push(
      `if out="$(${renderCommand(vector.flags)} 2>&1)"; then`,
      `  printf '%s\\n' "❌ ${vector.name}: the chart accepted unverified assembler output" >&2`,
      '  fail=1',
      `elif ! { ${reasons}; }; then`,
      `  printf '%s\\n' "❌ ${vector.name}: refused, but not because ${vector.because.join(' / ')}" >&2`,
      `  printf '%s\\n' "$out" | head -5 >&2`,
      '  fail=1',
      'fi',
      '',
    );
  }

  for (const vector of STABLE) {
    lines.push(
      `left="$(${readCommand(vector.left, vector.key)} 2>&1)"`,
      `right="$(${readCommand(vector.right, vector.key)} 2>&1)"`,
      'if [ -z "$left" ] || [ "$left" != "$right" ]; then',
      `  printf '%s\\n' "❌ ${vector.name}: '$left' != '$right'" >&2`,
      '  fail=1',
      'fi',
      '',
    );
  }

  lines.push(
    `printf '%s\\n' "✅ ${ACCEPTS.length} accepted, ${REFUSES.length} refused, ${STABLE.length} stable"`,
    'exit "$fail"',
    '',
  );
  return lines.join('\n');
}

const SCRIPT_PATH = 'probe-lpsm-vectors.sh';

export default defineSmoke({
  sandbox: { snapshot: 'git', preserve: ['.direnv'] },
  baseline: {
    name: 'baseline-wrapper-lpsm-hostnames-green',
    description:
      'Ordinary and optional-instance dotted derivation, namespace-sourced platform, separate-instance parsing, dash-fused rejection, and the preview boundary that accepts only verified assembler output.',
    async run(repo: any) {
      await withCleanProbeState(repo, [SCRIPT_PATH], async () => {
        await repo.write(SCRIPT_PATH, vectorScript());
        const command = `nix develop --no-write-lock-file .#ci -c bash ${SCRIPT_PATH}`;
        const result = await repo.exec(command, { timeoutMs: 900000 });
        if (result.exitCode !== 0) {
          throw new Error(`wrapper-lpsm-hostnames failed on the healthy repo: ${result.stderr || result.stdout}`);
        }
      });
    },
  },
});
