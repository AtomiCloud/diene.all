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

const PREVIEW = [
  '--set global.instance.preview.enabled=true',
  `--set-string contracts.lpsm.instanceZone=${PREVIEW_ZONE}`,
];

// The same five-slot dotted coordinate in the other two canonical zones: the ABSOL
// localhost zone a developer resolves locally, and the Boron/lapras canonical
// admin zone. Each moves a different slot as well as the zone, so a derivation
// that quietly reads a slot off the service tree instead of the LPSM contract
// cannot survive them the way it survives the committed defaults.
const LOCALHOST_ZONE = 'localhost';
const ADMIN_ZONE = 'admin.atomi.cloud';
const ABSOL = [
  '--set-string contracts.lpsm.landscape=absol',
  '--set-string contracts.lpsm.instance=run42',
  `--set-string contracts.lpsm.instanceZone=${LOCALHOST_ZONE}`,
];
const LAPRAS = [
  '--set-string contracts.lpsm.service=lithium',
  '--set-string contracts.lpsm.instance=kirin',
  '--set-string contracts.lpsm.landscape=lapras',
  `--set-string contracts.lpsm.instanceZone=${ADMIN_ZONE}`,
];

// The platform slot is the release namespace, never a values file. The refusal
// below proves the negative half; this proves the positive one by moving the
// namespace and the declared platform together and watching the slot follow.
const OTHER_NAMESPACE = 'otherplatform';

// A VALID hostname, independent of every slot the DNS-1123 vectors move. Left to
// its default, `parseHostname` is derived from the slot under test, so a vector
// that moved the landscape would be refused by the INVERSE parser reading the
// derived garbage and would prove nothing about the forward derivation. Pinning
// it makes the forward helper the only thing that can own those refusals.
const VALID_PARSE_INPUT = 'api.wrapper.sample.run001.example.local.example.invalid';
const PINNED_PARSE = `--set-string contracts.lpsm.parseHostname=${VALID_PARSE_INPUT}`;
const OVERLONG_LABEL = 'a'.repeat(64);

// The pre-minted physical instance pair. The authorized minter owns the
// repository qualification, the deterministic normalization, the stable hash that
// shortens a long id into one DNS label, and the collision audit; this chart only
// verifies boundary shape and records the pair. So the ACCEPT vectors below use an
// original far longer than one DNS label together with a short hash label, and
// prove BOTH exact values round-trip out of the contract while the hostname
// segment is the label alone.
const COMMITTED_ORIGINAL = 'github.com/AtomiCloud/diene.all/charts/helm-wrapper/pull-requests/12345';
const COMMITTED_LABEL = 'pr-12345-9f3a1c';
const LONG_ORIGINAL = `${COMMITTED_ORIGINAL}/attempt-7`;
const HASH_LABEL = 'wrapper-pr12345-7q2m9x';
const MINTED_PAIR = [
  `--set-string global.instance.original=${LONG_ORIGINAL}`,
  `--set-string global.instance.label=${HASH_LABEL}`,
];
// 254 bytes, still inside the character rule, so the only thing wrong with it is
// its length at either boundary.
const OVERLONG_ORIGINAL = `github.com/atomicloud/${'a'.repeat(232)}`;

// The forward derivation once accepted labels its own inverse parser rejects, so
// each DNS-1123 vector is asserted at BOTH boundaries in its own right: the
// generated values schema refuses the malformed value before a template runs,
// and the same bytes re-run under --skip-schema-validation reach the helper,
// whose named reason is then the only thing that can refuse. Asserting one half
// alone would let the helper go slack again behind the schema — which is exactly
// how the defect survived the first time.
const SKIP_SCHEMA = '--skip-schema-validation';
type Boundary = { name: string; flags: string[]; schema: string; helper: string };
const DNS_1123: Boundary[] = [
  {
    name: 'leading-dash-landscape-label',
    flags: ['--set-string contracts.lpsm.landscape=-example', PINNED_PARSE],
    schema: "at '/contracts/lpsm/landscape': '-example' does not match pattern",
    helper: 'HostnameLabelInvalid: landscape label "-example" must start with a lowercase alphanumeric byte',
  },
  {
    name: 'leading-dash-service-label',
    flags: ['--set-string contracts.lpsm.service=-wrapper', PINNED_PARSE],
    schema: "at '/contracts/lpsm/service': '-wrapper' does not match pattern",
    helper: 'HostnameLabelInvalid: service label "-wrapper" must start with a lowercase alphanumeric byte',
  },
  {
    name: 'trailing-dash-module-label',
    flags: ['--set-string contracts.lpsm.module=api-', PINNED_PARSE],
    schema: "at '/contracts/lpsm/module': 'api-' does not match pattern",
    helper: 'HostnameLabelInvalid: module label "api-" must end with a lowercase alphanumeric byte',
  },
  {
    name: 'trailing-dash-optional-instance-label',
    flags: ['--set-string contracts.lpsm.instance=run001-', PINNED_PARSE],
    schema: "at '/contracts/lpsm/instance': 'run001-' does not match pattern",
    helper: 'HostnameLabelInvalid: instance label "run001-" must end with a lowercase alphanumeric byte',
  },
  {
    name: 'sixty-four-byte-landscape-label',
    flags: [`--set-string contracts.lpsm.landscape=${OVERLONG_LABEL}`, PINNED_PARSE],
    schema: "at '/contracts/lpsm/landscape': maxLength: got 64, want 63",
    helper: `HostnameLabelInvalid: landscape label "${OVERLONG_LABEL}" is 64 bytes`,
  },
  // The zone vectors move `ordinaryZone`, which no parser ever reads, so the
  // forward derivation is the only boundary that can own them at all.
  {
    name: 'trailing-dash-zone-segment',
    flags: ['--set-string contracts.lpsm.ordinaryZone=bad-.atomi.cloud'],
    schema: "at '/contracts/lpsm/ordinaryZone': 'bad-.atomi.cloud' does not match pattern",
    helper:
      'HostnameLabelInvalid: zone label 1 of "bad-.atomi.cloud" "bad-" must end with a lowercase alphanumeric byte',
  },
  {
    name: 'empty-zone-segment',
    flags: ['--set-string contracts.lpsm.ordinaryZone=cluster..atomi.cloud'],
    schema: "at '/contracts/lpsm/ordinaryZone': 'cluster..atomi.cloud' does not match pattern",
    helper: 'HostnameLabelInvalid: zone label 2 of "cluster..atomi.cloud" is empty',
  },
  {
    // A leading dot is not a separator this boundary may absorb: trimming it
    // would repair an invalid zone into valid bytes before anything judged it.
    name: 'leading-dot-zone',
    flags: ['--set-string contracts.lpsm.ordinaryZone=.atomi.cloud'],
    schema: "at '/contracts/lpsm/ordinaryZone': '.atomi.cloud' does not match pattern",
    helper: 'HostnameLabelInvalid: zone label 1 of ".atomi.cloud" is empty',
  },
  {
    name: 'uppercase-zone-segment',
    flags: ['--set-string contracts.lpsm.ordinaryZone=cluster.Atomi.cloud'],
    schema: "at '/contracts/lpsm/ordinaryZone': 'cluster.Atomi.cloud' does not match pattern",
    helper:
      'HostnameLabelInvalid: zone label 2 of "cluster.Atomi.cloud" "Atomi" must start with a lowercase alphanumeric byte',
  },
  {
    name: 'inner-uppercase-zone-segment',
    flags: ['--set-string contracts.lpsm.ordinaryZone=cluster.atOmi.cloud'],
    schema: "at '/contracts/lpsm/ordinaryZone': 'cluster.atOmi.cloud' does not match pattern",
    helper:
      'HostnameLabelInvalid: zone label 2 of "cluster.atOmi.cloud" "atOmi" may hold only lowercase alphanumerics and internal dashes',
  },
];

// The same two-boundary treatment for the preview receipt. Each of these four used
// to be ONE vector whose `because` list was OR-joined, so a schema rejection stood
// in for the helper assertion and the helper could have stopped refusing entirely
// without a vector reddening. Split, each boundary owns exactly its own reason and
// the helper half is proven reachable after `--skip-schema-validation`.
const PREVIEW_RECEIPT: Boundary[] = [
  {
    name: 'unversioned-word-list',
    flags: [...PREVIEW, '--set-string global.instance.preview.receipt.wordList=diene.preview-wordlist'],
    schema: "at '/global/instance/preview/receipt/wordList': 'diene.preview-wordlist' does not match pattern",
    helper:
      'PreviewIdentityUnavailable: petname word list "diene.preview-wordlist" is not a versioned diene.preview-wordlist',
  },
  {
    name: 'petname-outside-the-grammar',
    flags: [
      ...PREVIEW,
      '--set-string global.instance.preview.canonical.previewPetname=otterbeatspotato',
      '--set-string global.instance.preview.receipt.previewPetname=otterbeatspotato',
    ],
    schema: "at '/global/instance/preview/canonical/previewPetname': 'otterbeatspotato' does not match pattern",
    helper: 'PreviewIdentityUnavailable: "otterbeatspotato" is not a versioned NOUN-VERB-NOUN petname',
  },
  {
    name: 'suffix-longer-than-three-characters',
    flags: [
      ...PREVIEW,
      `--set-string global.instance.preview.canonical.previewPetname=${SUFFIXED}9`,
      `--set-string global.instance.preview.receipt.previewPetname=${SUFFIXED}9`,
      `--set-string global.instance.preview.receipt.collision.liveFullLeaseDigest=${OTHER_DIGEST}`,
    ],
    schema: `at '/global/instance/preview/canonical/previewPetname': '${SUFFIXED}9' does not match pattern`,
    helper: `PreviewIdentityUnavailable: "${SUFFIXED}9" is not a versioned NOUN-VERB-NOUN petname`,
  },
  {
    name: 'fork-source-outside-the-ruled-pair',
    flags: [...PREVIEW, '--set-string global.instance.preview.receipt.forkSource=serving'],
    schema: "at '/global/instance/preview/receipt/forkSource': value must be one of 'staging', 'production'",
    helper: 'PreviewIdentityUnavailable: forkSource "serving" is neither staging nor production',
  },
];

// The physical instance pair. A long or repository-qualified original is now the
// ACCEPTED case — the old vectors refusing exactly that were false, because the
// chart's job is to RECORD the minter's pair, not to re-derive it. What is refused
// is a malformed half and a half with no partner.
const INSTANCE_PAIR: Boundary[] = [
  {
    name: 'uppercase-instance-label',
    flags: ['--set-string global.instance.label=PR-12345'],
    schema: "at '/global/instance/label': 'PR-12345' does not match pattern",
    helper: 'HostnameLabelInvalid: global.instance.label "PR-12345" must start with a lowercase alphanumeric byte',
  },
  {
    name: 'sixty-four-byte-instance-label',
    flags: [`--set-string global.instance.label=${OVERLONG_LABEL}`],
    schema: "at '/global/instance/label': maxLength: got 64, want 63",
    helper: `HostnameLabelInvalid: global.instance.label "${OVERLONG_LABEL}" is 64 bytes`,
  },
  {
    name: 'whitespace-bearing-physical-original',
    flags: [`--set-string 'global.instance.original=repository a/pr-123'`],
    schema: "at '/global/instance/original': 'repository a/pr-123' does not match pattern",
    helper:
      'InstanceOriginalInvalid: global.instance.original "repository a/pr-123" must start and end with an alphanumeric',
  },
  {
    // 253 bytes is the ceiling, not 63: shortening happens at the minter, and the
    // chart refuses only what no DNS name could ever record at all.
    name: 'two-hundred-fifty-four-byte-physical-original',
    flags: [`--set-string global.instance.original=${OVERLONG_ORIGINAL}`],
    schema: "at '/global/instance/original': maxLength: got 254, want 253",
    helper: 'InstanceOriginalInvalid: global.instance.original is 254 bytes',
  },
];

// A mint that had to disambiguate: the same base petname was already held live by
// an allocation with a DIFFERENT full digest.
const COLLIDED = [
  ...PREVIEW,
  `--set-string global.instance.preview.canonical.previewPetname=${SUFFIXED}`,
  `--set-string global.instance.preview.receipt.previewPetname=${SUFFIXED}`,
  `--set-string global.instance.preview.receipt.collision.liveFullLeaseDigest=${OTHER_DIGEST}`,
];

const pin = (key: string, value: string) => `--set-string 'global.instance.preview.manifest.pins.${key}=${value}'`;
const resolution = (key: string, field: string, value: string) =>
  `--set-string 'global.instance.preview.manifest.branchResolutions.${key}.${field}=${value}'`;

type Accepts = { name: string; flags: string[]; key: string; expected: string; namespace?: string };
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
    name: 'ordinary-four-slot-parse',
    flags: ['--set-string contracts.lpsm.parseHostname=api.wrapper.sample.example.local.example.invalid'],
    key: 'lpsm.parsed',
    expected: '{"instance":"","landscape":"example","module":"api","platform":"sample","service":"wrapper"}',
  },
  {
    name: 'non-preview-original-recorded-verbatim',
    flags: [],
    key: 'instance.original',
    expected: COMMITTED_ORIGINAL,
  },
  {
    name: 'non-preview-label-is-the-minted-label',
    flags: [],
    key: 'instance.label',
    expected: COMMITTED_LABEL,
  },
  // The round trip the old one-DNS-label input could not express at all: a
  // genuinely long repository-qualified original and the minter's short hash label
  // both come back out byte-for-byte, and the hostname carries the label alone.
  {
    name: 'long-repository-qualified-original-round-trips',
    flags: MINTED_PAIR,
    key: 'instance.original',
    expected: LONG_ORIGINAL,
  },
  {
    name: 'minted-hash-label-round-trips-beside-it',
    flags: MINTED_PAIR,
    key: 'instance.label',
    expected: HASH_LABEL,
  },
  {
    name: 'hostname-segment-is-the-minted-label',
    flags: MINTED_PAIR,
    key: 'instance.hostname',
    expected: `api.wrapper.sample.${HASH_LABEL}.example.local.example.invalid`,
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
  {
    name: 'absol-localhost-coordinate',
    flags: ABSOL,
    key: 'lpsm.instanceHostname',
    expected: `api.wrapper.sample.run42.absol.${LOCALHOST_ZONE}`,
  },
  {
    name: 'absol-localhost-parses-back',
    flags: ABSOL,
    key: 'lpsm.parsed',
    expected: '{"instance":"run42","landscape":"absol","module":"api","platform":"sample","service":"wrapper"}',
  },
  {
    name: 'boron-lapras-canonical-coordinate',
    flags: LAPRAS,
    key: 'lpsm.instanceHostname',
    expected: `api.lithium.sample.kirin.lapras.${ADMIN_ZONE}`,
  },
  {
    name: 'boron-lapras-parses-back',
    flags: LAPRAS,
    key: 'lpsm.parsed',
    expected: '{"instance":"kirin","landscape":"lapras","module":"api","platform":"sample","service":"lithium"}',
  },
  {
    name: 'platform-slot-follows-the-release-namespace',
    flags: [`--set-string serviceTree.platform=${OTHER_NAMESPACE}`],
    namespace: OTHER_NAMESPACE,
    key: 'lpsm.ordinaryHostname',
    expected: `api.wrapper.${OTHER_NAMESPACE}.example.cluster.atomi.cloud`,
  },
];

// Refusals. Each asserts the reason, not merely a non-zero exit, so a vector
// cannot pass because an unrelated render error happened to fire.
const REFUSES: Refuses[] = [
  {
    name: 'mint-time-name-is-immutable',
    flags: [...COLLIDED, `--set-string global.instance.preview.canonical.previewPetname=${PETNAME}`],
    because: ['recorded at mint'],
  },
  {
    name: 'full-digest-mismatch',
    flags: [...PREVIEW, `--set-string global.instance.preview.canonical.fullLeaseDigest=${OTHER_DIGEST}`],
    because: ['does not equal the receipt digest'],
  },
  {
    name: 'suffix-without-a-recorded-collision',
    flags: [
      ...PREVIEW,
      `--set-string global.instance.preview.canonical.previewPetname=${SUFFIXED}`,
      `--set-string global.instance.preview.receipt.previewPetname=${SUFFIXED}`,
    ],
    because: ['carries a collision suffix with no recorded live base-petname collision'],
  },
  {
    name: 'caller-supplied-suffix',
    flags: [
      ...PREVIEW,
      `--set-string global.instance.preview.canonical.previewPetname=${PETNAME}-abc`,
      `--set-string global.instance.preview.receipt.previewPetname=${PETNAME}-abc`,
      `--set-string global.instance.preview.receipt.collision.liveFullLeaseDigest=${OTHER_DIGEST}`,
    ],
    because: ['is not the first three base32hex digest characters'],
  },
  {
    name: 'same-digest-is-not-a-collision',
    flags: [...COLLIDED, `--set-string global.instance.preview.receipt.collision.liveFullLeaseDigest=${DIGEST}`],
    because: ['idempotent join, never a petname collision'],
  },
  {
    name: 'recorded-collision-must-show-in-the-name',
    flags: [...PREVIEW, `--set-string global.instance.preview.receipt.collision.liveFullLeaseDigest=${OTHER_DIGEST}`],
    because: ['carries no collision suffix'],
  },
  {
    name: 'unsigned-receipt',
    flags: [...PREVIEW, '--set-string global.instance.preview.receipt.signature='],
    because: ['the assembler receipt is missing'],
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
    flags: [...PREVIEW, `--set-string 'global.instance.preview.manifest.pins.auth\\.logto.ref=refs/heads/main'`],
    because: ['must carry exactly kind and version'],
  },
  // The pair is recorded together or not at all. A key removed outright is caught
  // by the generated schema's own `required` list; an emptied half reaches the
  // helper, which is the only boundary that can see one half without the other.
  {
    name: 'missing-instance-label-at-the-values-schema',
    flags: ['--set global.instance.label=null'],
    because: ["at '/global/instance': missing property 'label'"],
  },
  {
    name: 'missing-instance-label-at-the-instance-helper',
    flags: ['--set global.instance.label=null', SKIP_SCHEMA],
    because: ['InstancePairIncomplete: global.instance.original'],
  },
  {
    name: 'missing-instance-original-at-the-values-schema',
    flags: ['--set global.instance.original=null'],
    because: ["at '/global/instance': missing property 'original'"],
  },
  {
    name: 'missing-instance-original-at-the-instance-helper',
    flags: ['--set global.instance.original=null', SKIP_SCHEMA],
    because: ['InstancePairIncomplete: global.instance.label'],
  },
  {
    name: 'orphan-original-with-an-emptied-label',
    flags: ['--set-string global.instance.label='],
    because: ['InstancePairIncomplete: global.instance.original'],
  },
  {
    name: 'orphan-label-with-an-emptied-original',
    flags: ['--set-string global.instance.original='],
    because: ['InstancePairIncomplete: global.instance.label'],
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

// Every boundary pair becomes two separately named vectors, never one with two
// alternative reasons: an OR goes green the moment EITHER boundary carries the
// whole refusal, so the schema alone could keep a slack helper looking asserted.
// Each half here names exactly its own reason, and the helper half re-runs the
// same bytes under --skip-schema-validation so it is proven reachable.
function refusesAtBothBoundaries(vectors: Boundary[], helperName: string): void {
  for (const vector of vectors) {
    REFUSES.push(
      { name: `${vector.name}-at-the-values-schema`, flags: vector.flags, because: [vector.schema] },
      {
        name: `${vector.name}-at-the-${helperName}`,
        flags: [...vector.flags, SKIP_SCHEMA],
        because: [vector.helper],
      },
    );
  }
}

refusesAtBothBoundaries(DNS_1123, 'hostname-helper');
refusesAtBothBoundaries(PREVIEW_RECEIPT, 'preview-helper');
refusesAtBothBoundaries(INSTANCE_PAIR, 'instance-helper');

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

function renderCommand(flags: string[], namespace = 'sample'): string {
  return [
    `helm template helm-wrapper chart --namespace ${namespace} --values chart/values.example.yaml`,
    ...flags,
  ].join(' ');
}

function readCommand(flags: string[], key: string, namespace?: string): string {
  const selector = `select(.kind == "ConfigMap" and .metadata.name == "wrapper-contracts") | .data."${key}"`;
  return `${renderCommand(flags, namespace)} | yq -r '${selector}'`;
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
      `got="$(${readCommand(vector.flags, vector.key, vector.namespace)} 2>&1)"`,
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
      'Ordinary four-slot and optional-instance dotted derivation across the ENTEI dev, ABSOL localhost, and Boron/lapras canonical zones, namespace-sourced platform, separate-instance parsing of both arities, dash-fused rejection, a long repository-qualified physical original round-tripping beside its minted DNS-1123 label with the hostname carrying the label alone, and DNS-1123 label, dotted-zone, preview-receipt, and instance-pair refusals each proven at the values schema and again, separately named, at their own helper.',
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
