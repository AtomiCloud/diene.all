# npm release runbook

`@atomicloud/diene.result` publishes from the
[`AtomiCloud/diene.bun-result`](https://github.com/AtomiCloud/diene.bun-result)
mirror repository. The release workflow stamps the version in the release
commit, creates `vX.Y.Z`, and the tag-triggered CD workflow verifies that the
manifest version equals the tag before publishing.

The reusable publish workflow receives the organization secret
`NPM_API_KEY`. It uses `bun publish --access public --tolerate-republish`, so a
retry of an already-published tag is safe. Publishing never changes the
manifest.

## Token rotation

Rotate the granular npm token in npm, replace the `NPM_API_KEY` organization
secret, and rerun the most recent tag's failed CD job. Revoke the old token
after the replacement succeeds. Keep the token limited to the AtomiCloud
package scope and publication.

## Provenance

npm provenance remains deliberately disabled. It requires an OIDC trusted
publishing flow, while this repository uses the accepted API-key flow. Do not
add `--provenance` or grant `id-token: write`; revisit both together only if
the organization adopts trusted publishing.
