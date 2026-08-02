# Review Plan — Inline Step

This step runs inline (not delegated) because it requires user interaction.

## Task

Present the documentation plan to the user for review and approval.

## Steps

### 1. Read the Plan

Read `.contributor-docs/doc-plan.yaml`. Ask the state-agent to assess and provide the
fresh `planHash`; do not read state JSON directly. If the live file no longer matches
the hash recorded at classification, do not present or decide on the moving plan; report
the stale review state and invoke state-agent `invalidate-plan`. That named operation
proves the mismatch and returns to `classify`, where `record-classification` validates
and binds a replacement.

### 2. Present Summary

Display a structured summary to the user:

```
## Documentation Plan

### Modules
- <module name>: <description> (<N> features, <N> concepts, <N> algorithms, <N> surfaces)

### Shared
- <N> cross-cutting concepts
- <N> cross-cutting algorithms

### Architecture Decisions
- <N> ADRs

### Top-Level Files
- 00-overview.mdx
- 01-architecture/index.mdx
- 02-modules.mdx
- 03-development/ (<N> files)

### Total: <N> files across <N> tiers

Plan identity: <64-character planHash>
```

### 3. Ask for Approval

Use AskUserQuestion:

- "Does this documentation plan look correct?"
- Options: "Approve", "Revise" (with description field for feedback)

### 4. Handle Response

If approved:

- Invoke state-agent `approve-plan` with the explicit approval and the presented
  `planHash`. The operation chooses the fixed target object; do not send field patches.

If revise:

- Capture the user's feedback
- Invoke state-agent `reject-plan` with the non-empty feedback and presented
  `planHash`. The operation chooses the fixed target object; do not send field patches.

## Important

- This step MUST be inline — it requires user interaction
- Do NOT proceed to write without user approval
- The plan can go through multiple review cycles
- Use the state-agent for ALL state updates
- Bind either decision to the exact hash shown to the user
- Never present a non-current plan; use `invalidate-plan` to return it to classification
