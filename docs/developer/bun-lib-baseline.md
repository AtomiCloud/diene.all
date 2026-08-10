# Bun library baseline

The library build emits `dist/index.js`, `dist/index.cjs`, `dist/index.d.ts`,
and `dist/index.d.cts`. Run `pls build` for the four-artifact build and
`./scripts/ci/pkg-validate.sh` for tarball-content, metadata, publint, and
Are The Types Wrong validation.

Package identity comes from `package.json`. When promoting this template,
change the package name, description, repository URLs, keywords, README badges,
and the usage-skill namespace. Keep `src/index.ts` re-export-only and preserve
the conditional import/require declaration map.

Semantic release is the only version-stamping mechanism. Its prepare hook
invokes `scripts/release/bump.sh`, and the release commit carries the resulting
manifest version. Tag-triggered publishing verifies that version against the
tag and never mutates it.

Publishing uses the organization `NPM_API_KEY` secret and
`bun publish --access public --tolerate-republish`. npm provenance remains off
because this family deliberately uses API-key authentication instead of OIDC.
Rotate the granular npm token before expiry or immediately after suspected
exposure, replace the organization secret, and validate one tag release through
the mirror before revoking the previous token.
