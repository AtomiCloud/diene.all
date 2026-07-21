# Shared probe authoring helpers

These files are chain-side only and are inherited from the workspace branch. Probe
definitions import them with relative paths; generated repositories never receive them.

- `defineGate` emits exactly one healthy baseline and one meaningful mutation.
- `defineSmoke` emits a healthy baseline only.
- `definePresence` emits an exists/parses check only, represented by the contract-v1
  baseline kind.
- There is deliberately no `proven-once` builder: Q-G18 proofs never ship as probe rows.
- Structural mutators select replaceable targets by glob and pattern rather than by
  sample filename.

Each branch's `probes/features.json` remains the class ledger. Validate it against
`features.schema.json`; stripped or dormant mechanisms have no entry.
