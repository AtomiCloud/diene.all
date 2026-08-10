---
name: write-onboarding-gated-app
description: Gate an app on onboarding correctly — legal or consent step first, gating keyed PER BACKEND rather than globally, an existing-home user never seeing the picker, and allowlisted landscape discovery. Use when adding an onboarding flow, a home or tenant picker, a consent step, or per-backend readiness gating.
invocation:
  - write-onboarding-gated-app
  - onboarding
  - onboarding-gate
  - home-picker
---

# Write an Onboarding-Gated App

Copy the shape from `src/app/[locale]/onboarding/page.tsx` and
`src/components/picker/PickerFlow.tsx`. The gate is keyed PER BACKEND the route
actually needs — blocking a route on a backend it does not use is a defect. The
legal or consent step precedes everything else, and an existing-home user never
sees the picker.

Follow the rules in
**[frontend-ux/patterns — Onboarding-gated app](../../../docs/standards/frontend-ux/patterns.md#onboarding-gated-app)**,
then run [`frontend-ux-check`](../frontend-ux-check/SKILL.md) over the result.

Session and home-claim handling comes from
[`write-protected-page`](../write-protected-page/SKILL.md).
