# Frontend UX Patterns

The five canonical recipes this template ships, each with the real code path to
copy from. Every recipe is a specialization of
[the frontend UX checklist](./index.md) — the checklist still runs in full; these
pages only record the shape that satisfies it for a recurring job.

Each pattern has a thin skill under `.claude/skills/` that triggers on the job
and points back here.

| Pattern                | Skill                        | Copy from                                                                        |
| ---------------------- | ---------------------------- | -------------------------------------------------------------------------------- |
| Search bar (url-bound) | `write-search-bar`           | `src/components/home/SearchBar.tsx`, `src/adapters/hooks/useUrlState.ts`         |
| Page (pure renderer)   | `write-page`                 | `src/app/[locale]/page.tsx`                                                      |
| Protected page         | `write-protected-page`       | `src/adapters/auth/guard.ts`, `src/app/[locale]/settings/page.tsx`               |
| Onboarding-gated app   | `write-onboarding-gated-app` | `src/app/[locale]/onboarding/page.tsx`, `src/components/picker/PickerFlow.tsx`   |
| Form                   | `write-form`                 | `src/components/settings/SettingsForm.tsx`, `src/adapters/hooks/useFormDraft.ts` |

---

## Search bar (url-bound)

The canonical url-as-state recipe. Typing updates local state immediately and
mirrors into the URL through a debounced `replaceState`; pasting that URL into a
new context restores the same state.

Rules that apply beyond the base checklist:

- The hook owns the URL, the component owns nothing. `useUrlState(defaults)`
  returns `[state, setState]` and the `defaults` object is a call-site literal
  captured on first render.
- The SERVER reads `searchParams` on load and renders from it; the CLIENT never
  re-reads the URL to derive state after mount except on `popstate`.
- Never `push` per keystroke — `replaceState`, debounced, so back and forward
  stay meaningful.
- `type="search"` with `inputMode="search"` and `enterKeyHint="search"`; a real
  `<label>` bound by `htmlFor`; the input is at least 44px tall with a visible
  focus ring.
- The result region below is a state trio: loading, empty, error.

## Page (pure renderer)

Pages are PURE RENDERERS. `scripts/validate/pure-renderer.ts` enforces it as a
blocking gate.

- A page may read `params`, call `setRequestLocale`, read translations, and
  mount components. It may NOT import a service, open a data connection, or hold
  business logic.
- Data comes from a client component that resolves its dependency through the
  module registry, or from a server adapter under `src/adapters/**`.
- Every page sets the locale before rendering translated content, and the
  locale layout supplies the SSR-injected landscape and client-safe config.
- `export const runtime = 'edge'` is FORBIDDEN
  (`scripts/validate/forbidden-runtime.ts`); the Node runtime is the only one
  the OpenNext adapter supports.

## Protected page

Server-side auth guard first, render second.

- The guard is a server adapter (`requireSession`), never a client check. It
  runs before any protected content renders.
- The login redirect CARRIES `returnTo` with both path AND query, so the user
  lands back on the exact URL they asked for.
- Every sign-in checks the home claim: present means go home, absent means go to
  the picker. A protected page never assumes the claim exists.
- The page stays a pure renderer — `await requireSession(...)` then render.

## Onboarding-gated app

The gate is per BACKEND the route actually needs, not global.

- The legal or consent step precedes everything else in the flow.
- An existing-home user NEVER sees the picker; the guard's decision drives the
  redirect.
- Landscape discovery is allowlisted by endpoint suffix and the issuer is always
  baked — a non-allowlisted host is rejected before any request.
- The picker's ping stage is a state trio with skeletons that reserve the final
  row height, so confirming does not shift the layout.
- Blocking a route on a backend it does not need is a defect: gate keyed per
  backend, so a route ready on backend A renders while B is still onboarding.

## Form

The form-lifecycle recipe: drafts, live validation, clear-on-submit, and
reactive controls.

- Draft values persist to local storage as the user types and survive refresh.
  They clear on exactly four triggers: submit, reset, cancel, close.
- A restored draft ANNOUNCES itself (`role="status"`) rather than silently
  repopulating.
- Each field validates live, debounced, against its own schema, and the server
  re-validates on submit. The field never rewrites the user's value.
- `autocomplete`, `inputmode`, and `enterkeyhint` are required props on
  `Field` — a consumer cannot ship a field without them.
- Amounts use the keypad input, selectors use the bottom sheet, and the submit
  control is an `AsyncButton` so it disables with a spinner until settle.
- On submit failure, render the focused error summary described in
  [section B](./index.md#b-validation-and-forms).

---

## Related

- [Frontend UX](./index.md) — the checklist every pattern still satisfies.
- [Frontend UI trend](../frontend-ui-trend/index.md) — the current visual pick.
- [Identity](../../domain/identity.md) — palette, UI language, and voice.
