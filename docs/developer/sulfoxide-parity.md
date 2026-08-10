# Sulfoxide parity and the Garden doctor

Garden consumes sulfoxide's canonical member definitions. It never owns a second
membership list, and a profile may omit a member but never substitute another version.

## Where a member is authored

Each member is authored exactly once, in its declared `home`:

- `sulfoxide/members/*.yaml` — the sulfoxide-home members, authored here.
- `sulfoxide/import.yaml` — a pointer to the Primordial-home export. Primordial members
  are resolved through that pointer; copying them into this tree would create the second
  roster the environment contract forbids.

The roster is the unique union of those two sets. Parity means common schema and
profile-enum compatibility, valid cross-references, and Garden's installed tuple matching
the owning definition — never duplicate entries.

`sulfoxide/fixtures/` is test data. `garden-render.sh` refuses to read it unless
`DIENE_PARITY_FIXTURES=true` is set, so no fixture can quietly become a real roster.

## Definition shape

```yaml
id: cobalt
home: sulfoxide
owner: charts/cobalt
chartRef:
  repository: oci://ghcr.io/atomicloud/diene.all/charts/diene-cobalt
  version: 0.1.0
  digest: null # filled by Kargo promotion
  promotion: { state: pending, owner: charts/cobalt, reason: chart-not-yet-promoted }
imageRefs:
  - ref: ghcr.io/external-secrets/external-secrets:v2.7.0
    digest: sha256:6615aaea...
profiles:
  lapras: { state: include }
  # ... all seven landscapes, every omission carrying a stable reason code
```

Every definition declares all seven workload landscapes. An unpinned reference must state
its `pending` reason: the doctor reports a pending pin and never assumes it.

## Rendering and the doctor

```bash
pls garden:render -- eevee        # normalized report on stdout
pls garden:doctor                 # definition mode over all seven profiles
pls garden:doctor:installed       # compares a real installed tuple
```

`garden-render.sh` reads the owning definitions, rejects a member authored in two homes,
and emits `diene-garden-parity-report/v1` with the source digest, included members, their
pins, and every omission with its reason. The report is derivative evidence, not an
authority.

`garden-doctor.sh` adds the assertions:

- every omission carries a reason, in every profile;
- every included image resolves to a real digest or declares its pending state; and
- in `installed` mode, every installed digest is one the owning definition names.

`DIENE_INSTALLED_FILE` supplies the installed tuple as
`{"<profile>": {"<member>": {"images": ["sha256:..."]}}}`.

## The hosted filter

A hosted vcluster is a truncated LAPRAS environment. It drops only the public edge that
ENTEI already owns:

| Member                | Hosted                                  | Local                                              |
| --------------------- | --------------------------------------- | -------------------------------------------------- |
| platinum (kgateway)   | excluded — `entei-owns-shared-edge`     | included                                           |
| sulfur (cert-manager) | excluded — `entei-owns-shared-edge`     | excluded unless a local consumer requires it       |
| zinc (cluster issuer) | excluded — `entei-owns-shared-edge`     | excluded unless a local consumer requires it       |
| boron                 | excluded — `entei-owns-shared-edge`     | connected laptop profiles only                     |
| cobalt (ESO)          | included                                | included; controller-only on the hermetic profiles |
| dragonfly-operator    | included                                | included                                           |
| fleet-operator        | included as the local dependency subset | same                                               |
| lithium (local Logto) | included                                | included                                           |

Hosted profiles are not thin application-only compute, so the retained half is asserted
as strictly as the excluded half.

## Pinned OSS vcluster guard

`nix/snapshots/entei-vcluster.json` is one atomic bundle. `garden-parity.sh vcluster-lock`
requires digest pins throughout and rejects a Pro image, Platform endpoint, license path,
telemetry dependency, or floating version.

## Chart pins are pending

The sulfoxide wrapper charts are not promoted yet, so `chartRef.digest` is `null` with an
explicit `promotion.state: pending` naming the owning node. Upstream image digests are
real and asserted today. When Kargo promotes a chart, its digest lands in the owning
definition and the doctor's `installed` mode compares it without any other change.

## Producing the installed tuple from a live cluster

`garden-installed-tuple.sh <profile>` turns a real pod inventory into the tuple the doctor
compares. It reads `status.containerStatuses[].imageID`, which is the digest the kubelet
actually resolved, so a manifest tag can never stand in for what is really running. A
member owns a pod through the `atomi.cloud/service` label the charts already stamp, so no
second mapping table is introduced.

```bash
./scripts/local/garden-installed-tuple.sh eevee > tuple.json          # live cluster
DIENE_PODS_JSON=pods.json ./scripts/local/garden-installed-tuple.sh eevee   # captured inventory
DIENE_INSTALLED_FILE=tuple.json ./scripts/local/garden-doctor.sh installed eevee
```

By default the comparison also requires completeness: an included member that is not
running is reported as `NOT-INSTALLED`. Set `DIENE_INSTALLED_SUBSET=true` to check only the
members present in the tuple, which is the right mode for a partial inventory and never
the right mode for a readiness gate.

## Image indexes and platform digests

A pinned image is usually an OCI image index, and the digest a kubelet reports in
`imageID` may be a platform child of that index rather than the index digest itself. Both
name the same artifact, so a definition may record the children alongside the index digest:

```yaml
imageRefs:
  - ref: ghcr.io/external-secrets/external-secrets:v2.7.0
    digest: sha256:6615aaea... # the index digest
    platformDigests:
      - sha256:04b0d005... # linux/amd64 child of that index
```

The doctor accepts the index digest or any recorded child. Without this the doctor would
report drift on a correct install the first time it ran against a real cluster, which is a
false positive in the assertion it exists to provide. The `platform-digest-acceptance` gate
proves both are accepted, proves the two inventories genuinely differ so the check is not
vacuous, and proves an unrelated digest is still drift, so the widening does not blunt it.
