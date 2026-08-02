# Shared probe authoring helpers

These files are chain-side only and are inherited from the workspace branch. Probe
definitions import them with relative paths; generated repositories never receive them.

The builders are exported from [`definition.ts`](definition.ts), re-exported through
[`index.ts`](index.ts). Read `definition.ts` to see which builders exist and what each
one emits: the `EvidenceClass` union names the evidence classes, and each exported
`define*` function's body shows the probe rows it produces — a `kind: 'baseline'` row
for a healthy run, and a `kind: 'mutation'` row where the class requires the check to
be shown failing.

Two things are policy rather than code detail:

- There is deliberately no `proven-once` builder: Q-G18 proofs never ship as probe rows.
- Structural mutators select replaceable targets by glob and pattern rather than by
  sample filename.

Each branch's `probes/features.json` remains the class ledger. Validate it against
[`features.schema.json`](features.schema.json); stripped or dormant mechanisms have no
entry.
