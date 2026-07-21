# Neutral C0 Config and Problem fixture release

`c0-fixtures-r1` is the single committed, versioned, machine-readable source
for the C0 Config (§3) and Problem (§2 and §14) cases. It is owned by the
conductor/C0-contracts authority, not by either Dart owner package.

- `RELEASE.json` identifies the release and pins its prose sources.
- `SHA256SUMS` exhaustively authenticates the cases, provenance, and this
  README.
- `cases/*.json` are the normative machine source.
- `provenance/*.md` records verbatim source excerpts and the update process.

Owner packages merge this release commit and generate their Dart and JSON
projections from it. Nothing under `contracts/c0/` and no generated projection
may be hand-edited downstream. A content change requires a new release ID,
digest, independent release review, owner merges, regeneration, and owner
rereviews.

JSON files use recursively sorted keys, integers only, LF endings, and one
trailing newline. `RELEASE.json` is compact-canonical; case files are
pretty-canonical with two-space indentation. The complete release digest is
SHA-256 over the domain separator, the compact-canonical manifest without its
`releaseDigest`, and the exact committed `SHA256SUMS` bytes.
