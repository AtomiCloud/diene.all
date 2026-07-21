### §14 Problem catalog schema

- Each service publishes a `Problem` catalog CR (per service × landscape)
  with a `problems[]` list, each entry:
  `{ id, type: <RFC 9457 URI, per §2's template>, title, status,
  recoverable: bool, data: <JSON Schema of the `data` extension>,
  endpoints: [{ method, path }, …] }`.
- erbium merges per (platform × service) and renders the CF Worker error
  portal (schema + display); the traffic controller ADDITIONALLY publishes
  a derived static catalog doc per platform × tier to the same edge hosts
  advertised by Doc A, the fleet doc (§10) — frontends classify errors from
  the EDGE copy and never call Primordial, including during error storms.
- **The uncatalogued ⇒ 5xx ⇒ catalog-loop rule (MUST)**: any problem not yet
  in the catalog SHOULD surface as a 5xx (never a silently-swallowed
  catalogued shape); every such occurrence feeds a catalog-update loop —
  account for it, add a `Problem` entry for it in the service repo, next
  release re-materializes the CR, erbium/traffic controller republish. The
  frontend's recoverable/fatal split (§2) depends on the catalog being
  complete, so this loop is how it stays complete.
