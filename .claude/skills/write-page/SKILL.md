---
name: write-page
description: Add an App Router page that stays a pure renderer — reads params, sets the locale, reads translations, mounts components, and imports no service. Use when creating a new route or restructuring an existing page.
invocation:
  - write-page
  - new-page
  - add-route
  - pure-renderer
---

# Write a Page (pure renderer)

Copy the shape from `src/app/[locale]/page.tsx`. A page reads `params`, calls
`setRequestLocale`, reads translations, and mounts components — it never imports
a service or holds business logic. `scripts/validate/pure-renderer.ts` is a
blocking gate, and `export const runtime = 'edge'` is forbidden
(`scripts/validate/forbidden-runtime.ts`).

Follow the rules in
**[frontend-ux/patterns — Page](../../../docs/standards/frontend-ux/patterns.md#page-pure-renderer)**,
then run [`frontend-ux-check`](../frontend-ux-check/SKILL.md) over the result.

Ownership boundary for anything the page pulls in:
[Next.js baseline](../../../docs/developer/nextjs-baseline.md).
