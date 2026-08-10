# Ubiquitous language: Config

The shipped surface lives in `Lib`; the demo consumer that composes it lives in
`App`, and the fakes consumers test against live in `TestHelper`.

| Term          | Meaning                                                                                |
| ------------- | -------------------------------------------------------------------------------------- |
| Layer         | One source of configuration values. Base, landscape overlay, and environment.          |
| Base layer    | The required file carrying FULL defaults. Every key a service reads exists here.       |
| Landscape     | The deployment a service runs in. Identity, never a secret.                            |
| Overlay       | The sparse landscape file naming only what differs from the base layer.                |
| Environment   | The prefixed variable layer, applied LAST and beating both files.                      |
| Env prefix    | The per-app marker identifying which variables are this app's. Required, never baked.  |
| Canonical key | A key with separators dropped and casing folded, so every C0 spelling is one key.      |
| Block         | One option type bound at one config key, exported by the engine that reads it.         |
| Root schema   | The union of every block a service registers, rendered as one JSON schema.             |
| Drift         | The committed schema no longer matching the registered blocks. CI reds on it.          |
| Fail-fast     | Rejecting the process at startup when the FINAL merged layer does not validate.        |
| Blank-in-yaml | A secret declared as an empty key in the base layer and injected from the environment. |

Say "layer", "overlay", "block", and "merged" consistently. There is no merge
engine to name: provider layering IS the merge, so "merge" describes the result
of ordering layers, never a component.

Avoid "loader", "registry of values", or "config service" — the library is a set
of `IConfiguration` providers plus option registration, and naming it otherwise
invites the parallel config engine this port deliberately does not have.
