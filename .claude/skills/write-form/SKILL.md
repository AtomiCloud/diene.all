---
name: write-form
description: Build a form with the full lifecycle — drafts that persist as the user types and clear on exactly submit, reset, cancel, and close; live debounced per-field validation that never rewrites the value; required autocomplete, inputmode, and enterkeyhint; an AsyncButton submit that disables with a spinner; and a focused error summary on failure. Use when adding or changing any form, input, or field.
invocation:
  - write-form
  - form
  - add-form
  - form-draft
  - field
---

# Write a Form

Copy the shape from `src/components/settings/SettingsForm.tsx`, persist with
`src/adapters/hooks/useFormDraft.ts`, and build every input from
`src/components/ui/Field.tsx`. Drafts survive refresh and clear on exactly four
triggers — submit, reset, cancel, close. A restored draft ANNOUNCES itself
rather than silently repopulating.

Follow the rules in
**[frontend-ux/patterns — Form](../../../docs/standards/frontend-ux/patterns.md#form)**,
then run [`frontend-ux-check`](../frontend-ux-check/SKILL.md) over the result.

Reach for the specialized controls rather than a bare input: `AmountInput` for
amounts, `SelectSheet` for selectors, `AsyncButton` for submit.
