# {Alert base name}

> Covers: 🚨 {critical name} · ⚠️ {warning name} (whichever tiers exist)
> Context: [System overview](../../overview.md) · [Dashboard panel]({url}) · Escalation: #{channel}

{Meaning + user impact — 2 sentences, plain language.}

## Triage

1. {First check — the fastest discriminator:}

   ```bash
   {command}
   ```

   {What the output means. Normal: {X}. Bad: {Y} → step {N}.}

2. {Next check:}

   ```promql
   {query}
   ```

## Remediation

- **{Likely cause 1}**: {fix steps}. Confirm with:

  ```bash
  {verification command}
  ```

- **{Likely cause 2}**: {fix}. Confirm with: `{command}`

Known cause: {YYYY-MM-DD} — {one-line incident summary}.

## Escalation

If not resolved in {30m}, or {condition}, escalate to {team/escalation chain} via #{channel}. Declare an incident if {user-impact condition}.
