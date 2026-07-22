# C0 fixture provenance — `identity.json`

This directory vendors an authoritative C0 conformance fixture, byte-for-byte,
so `diene_e2e` can bind its app-handoff (deferred-login) tests to the
independently-accepted contract release rather than to prose alone.

## Release

| Field           | Value                                                              |
| --------------- | ------------------------------------------------------------------ |
| releaseId       | `c0-fixtures-r2`                                                   |
| contractVersion | `2`                                                                |
| releaseDigest   | `0e64439c681a22fb4f02285c082ed8ffb7b465e732fde4e49757e9e3c9a5783e` |
| source commit   | `27c1807801397e2b1d05ab8b822a9f915fe03316`                         |
| local branch    | `c0-fixtures-r2-mrvv9ohy-e4288722`                                 |

## Vendored blob

| File            | SHA-256                                                            |
| --------------- | ------------------------------------------------------------------ |
| `identity.json` | `add399f33101bd68b98ac6aea3f073d6f7e852410cba5e846c7311ce2028ac59` |

The bytes are the exact contents of `contracts/c0/cases/identity.json` at source
commit `27c1807`, piped straight from `git show` with no reformatting. The path
`/test/fixtures/c0/identity.json` is listed in the node's `.prettierignore` so
treefmt/prettier never rewrites it and the SHA-256 above stays verifiable. This
matches the R2 release's own formatter policy, which excludes this exact path.

## Independent review / acceptance

- Independent review: brady `mrvwanl9-17453ed1` — verdict ACCEPT `a65c63ea`.
- Enabling coordination update: anastasia, Turn-052 / RB-357 disposition, which
  moved the authoritative C0 fixture from ABSENT to the released R2 artifact
  consumed here.

## Scope

This node consumes ONLY the `identity` domain of the release — the C0 §7
app-handoff vectors. The release's other domains (config, problem, result-wire)
are out of this node's scope and are not vendored or asserted here.
