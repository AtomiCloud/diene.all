# Observability O1 Add-Back Checklist

This is chain-side conductor material. It is not a CyanPrint feature row and is
excluded when the branch becomes a materialized repository.

## Preconditions

- The `observability` payload head is committed, clean, and locally green.
- The direct parent of the add-back is committed and green.
- No consumer-owned implementation has been authored on the add-back branch.

## Merge each add-back

Merge the same `observability` payload branch head into:

- `bun-base-w-observability`
- `bun-base-wo-helm-docker-w-observability`
- `dotnet-base-w-observability`
- `go-base-w-observability`

For each branch:

1. Merge the direct parent when it has advanced.
2. Merge the `observability` payload branch with a merge commit; never rebase,
   squash, cherry-pick, or re-author O1 files.
3. Confirm the add-back delta equals the payload delta exactly. This is a
   conductor S27 sweep, not a repository probe or CI feature.
4. Confirm the payload's probe files and `features.json` rows arrived through
   the merge itself.
5. Run the complete inherited CyanPrint matrix and branch CI-equivalent suite.
6. Record the parent, payload, merge commit, reports, and zero-negative verdicts.

## Cascade after all four are green

- Merge each add-back only into its direct children.
- Re-run every child's local proof/CI suite after the merge.
- Keep consumer OTel/Faro gates with the consumer nodes; do not move them into
  this payload matrix.
- Stop before any ENV-dependent Garden/preview proof until its owning graph is
  ready.
