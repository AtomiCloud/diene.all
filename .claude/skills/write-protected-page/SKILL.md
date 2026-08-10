---
name: write-protected-page
description: Add a page behind authentication — a server-side guard runs before any protected content renders, the login redirect carries returnTo with both path and query, and every sign-in checks the home claim. Use when a route needs a session, or when wiring login redirects and post-login landing.
invocation:
  - write-protected-page
  - protected-page
  - auth-guard
  - require-session
---

# Write a Protected Page

Copy the shape from `src/app/[locale]/settings/page.tsx` and guard it with
`src/adapters/auth/guard.ts`. The guard is a SERVER adapter, never a client
check. The login redirect carries `returnTo` with path AND query, and every
sign-in checks the home claim: present means go home, absent means go to the
picker.

Follow the rules in
**[frontend-ux/patterns — Protected page](../../../docs/standards/frontend-ux/patterns.md#protected-page)**,
then run [`frontend-ux-check`](../frontend-ux-check/SKILL.md) over the result.

The page still stays a pure renderer — see
[`write-page`](../write-page/SKILL.md).
