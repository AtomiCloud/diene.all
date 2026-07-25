# Frontend UX

The TIMELESS layer of frontend quality: state placement, forms, responsive
behavior, mobile ergonomics, feedback, error flow, and accessibility. Every item
here runs on ANY UI work and the loop repeats until all of them clear. Nothing
in this document expires — the dated, swappable visual pick lives in
[frontend UI trend](../frontend-ui-trend/index.md), and the per-app flavour
lives in [the identity document](../../domain/identity.md).

This standard is validated against WCAG 2.2, Core Web Vitals, NN/g, and platform
guidance; where those sources conflict with the rules below, the rules below win.

## The three layers

| Layer                | Lifetime            | Lives in                                            |
| -------------------- | ------------------- | --------------------------------------------------- |
| 1. UX thoughtfulness | Timeless, mandatory | This document                                       |
| 2. UI trend          | Dated, swappable    | [frontend-ui-trend](../frontend-ui-trend/index.md)  |
| 3. Identity          | Per app, mandatory  | [docs/domain/identity.md](../../domain/identity.md) |

## How it is enforced

Three vehicles, no doctrine probe matrix:

1. **This document** — the checklist below is the authority.
2. **Thin skills** — `frontend-ux-check` loops the checklist over any UI work;
   `vision-loop` runs the render-and-look pass of section H. The five
   [UX patterns](./patterns.md) each have their own thin skill.
3. **Rule-defaulting components** — the template's components make the correct
   behavior the DEFAULT, so a consumer cannot forget it (`AsyncButton`,
   `Field`, `SelectSheet`, `AmountInput`, `Skeleton`, `ErrorTier`,
   `SafeAreaShell`).

Mechanical gates cover only the trivially checkable subset:
`scripts/validate/pure-renderer.ts`, `scripts/validate/i18n-keys.ts`,
`scripts/validate/rebrand-static.ts`, and the non-pixel overflow assertion in
`tests/e2e/resize-fluid.spec.ts`. **There are no golden images and no screenshot
gates** — visual quality is reviewed by a human or a vision model, never
diffed against a pixel baseline.

---

## A. State placement

- [ ] The URL carries shareable state (search, filters, selection), updated in
      REAL TIME. Litmus test: "if I share this link, does capturing the current
      state benefit the receiver?"
- [ ] On page LOAD the URL state drives the SERVER-side render; on client
      interaction the URL updates WITHOUT a reload and the work runs
      client-side. The template binding is `src/adapters/hooks/useUrlState.ts`
      over the `urlstate` module of `@atomicloud/diene.frontend-utils`.
- [ ] Forms NEVER live in the URL. Forms persist to local storage so they
      survive disconnect and restart (`src/adapters/hooks/useFormDraft.ts`).
      They clear on cancel, close, submit, and reset — all fields. Accidental
      dismissal (backdrop tap, back gesture) offers a restore instead of
      silently wiping.
- [ ] Within a flow the user never re-types what they already entered
      (WCAG 3.3.7).

## B. Validation and forms

- [ ] Validation is two-layer: LIVE as the user edits (the feedback is the
      point) plus always re-verified server-side.
- [ ] Validate on input or change events, never keyup hacks. Never rewrite the
      user's field value. Never block paste, and never require the user to
      remember something at login (WCAG 3.3.8).
- [ ] Correct `autocomplete` on every field (`username`, `current-password`,
      `new-password`, `cc-*`, address fields) with stable ids — password
      managers must work. `Field` makes `autoComplete` a required prop.
- [ ] `inputmode` and `enterkeyhint` on every native text input kept — also
      required props on `Field`.
- [ ] On submit failure, render an error SUMMARY that takes focus, lists every
      error, and links each one to its field, in addition to the inline errors.

## C. Responsive and visual

Reviewed through the vision loop only — no golden baselines, no snapshot gate.

- [ ] Review representative mobile, tablet, and desktop sizes in dark AND
      light. Contrast floors: text 4.5:1, UI/icons/borders 3:1, in both themes.
      Screenshots are review INPUTS, never pixel baselines.
- [ ] The page BODY never scrolls horizontally. Deliberately wide content
      (carousels, wide tables) scrolls inside its OWN container.
- [ ] Mobile unwraps the card (thin margins); desktop is card-wrapped.
- [ ] Padding and margins are always present, differ between mobile and
      desktop, and are consistent within a breakpoint.
- [ ] Placement is balanced — one side or centered. GROUP buttons (confirm and
      skip on the right, back on the left). On mobile the button group spreads
      to the full width of the component above it.
- [ ] Prefer FIXED sizing over dynamic so nothing shuffles or reflows. This is
      Cumulative Layout Shift; the CI floor is CLS <= 0.1. Loaders that replace
      content reserve the final dimensions (`Skeleton`).
- [ ] Action coloring encodes the path: primary for the default path, caution
      (red or grey) for destructive, ghost or outline for the unlikely choice
      placed on the other side. The identity palette may re-tint the ROLE, never
      reassign it.
- [ ] Text-expansion tolerant: translated labels grow 200-300%, so no
      hard-clipped fixed-width labels. Logical CSS only
      (`margin-inline-start`, `text-align: start`) so RTL is free. Dates,
      numbers, currency, and plurals go through `Intl.*` only.

## D. Mobile ergonomics

- [ ] Action buttons sit at the BOTTOM for thumb reach, which makes SAFE-AREA
      insets mandatory on all edge-anchored UI (`src/components/shell/SafeAreaShell.tsx`
      over the `--safe-area-*` variables in `src/styles/globals.css`).
- [ ] Interactive targets are designed at 44-48px. The 24px WCAG 2.2 floor is
      the legal minimum, never the design target.
- [ ] THE OS KEYBOARD IS ONLY FOR GENUINE FREE TEXT. Non-typing inputs never
      summon it: amounts, PINs, and quantities use a custom keypad, inline or in
      a bottom sheet (`src/components/ui/AmountInput.tsx`); selectors use a
      MODAL bottom sheet, never a native dropdown or a navigate-away
      (`src/components/ui/SelectSheet.tsx`); dates and times use pickers; small
      quantities use steppers. Every keyboard-triggering field gets a reflow
      audit.
- [ ] Back-gesture safety: horizontal swipes stay out of the OS edge zones,
      system back never traps the user, and scroll position restores on back
      navigation.
- [ ] Pull-to-refresh is never the only refresh path. Haptics use system
      patterns only and feature-detect to a no-op on web.

## E. Feedback and loading — the 100ms bar

- [ ] EVERY interaction gets instant feedback. The family bar is ~100ms (human
      reaction time); the Core Web Vitals INP budget of 200ms is only the outer
      CI floor, far too slack as a design target.
- [ ] Async buttons put the spinner INSIDE the button, LEFT of the text, and
      disable the control until the action settles — no dead clicks, no double
      submit (`src/components/ui/AsyncButton.tsx` over
      `src/adapters/hooks/useAsyncAction.ts`).
- [ ] Content-changing async work replaces the content with a loader: a Lottie
      or a skeleton, both sanctioned; skeletons additionally reserve the final
      dimensions. Debounce the CONTENT loader ~100ms so fast operations never
      flash. The button spinner is NOT debounced.
- [ ] Every data view designs the STATE TRIO — loading, EMPTY, error. The empty
      state is the one everyone forgets: say what it means and what to do next.
- [ ] Destructive-but-reversible actions execute immediately with a ~5s undo.
      Confirmation dialogs are only for the truly irreversible.
- [ ] Toasts carry passive, low-severity notices ONLY — never errors, never
      actionable content. They are `aria-live` regions and dwell for at least
      5 seconds. The template ships no toast component; a product that adds one
      owns these rules.

## F. Error flow

Spend a lot of effort here. Classification is local plus the server's
edge-published Problem catalog and its `recoverable` flag
(`src/lib/error-classification/index.ts`, rendered by
`src/components/ui/ErrorTier.tsx`).

- [ ] Tier 1, retryable: instant inline feedback plus a retry affordance.
- [ ] Tier 2, server error: tell the user WHAT TO DO and stay on the page —
      never bounce to an error page.
- [ ] Tier 3, failure: full-page failure state where the user can COPY the
      error structure for support. Uncatalogued Problems are Tier 3 AND get
      reported so they feed the catalog loop.
- [ ] Offline: a branded offline fallback with auto-retry on the `online`
      event, paired with the form persistence of section A.

## G. Accessibility mechanics (WCAG 2.2)

- [ ] Everything is keyboard operable and focus is ALWAYS visible — a real
      ring, about 2px, 3:1 contrast — and never hidden under sticky headers,
      footers, or toasts.
- [ ] `prefers-reduced-motion` is honored and every animation is disableable
      (the global reset lives in `src/styles/globals.css`; `Lottie` freezes on
      its first frame).

## H. The vision loop

- [ ] NEVER guess. Render, LOOK at it, fix, repeat across representative
      viewports and both themes until it looks good. Screenshots feed human or
      vision review only; golden baselines and screenshot gates are forbidden.
      The `vision-loop` skill drives this pass.

## I. Trend and identity conformance

- [ ] NO EMOJI as UI elements — ever. Not icons, buttons, logos, or empty
      states. Emoji appear only inside user content. Use the app's ONE icon set
      and real logo assets.
- [ ] Logos are REAL, COLORED assets: brand SVGs in their brand colors, never
      stripped to monochrome by default, never stretched, distorted, or
      arbitrarily recolored. Third-party marks use their official colored
      logos. Clear space and minimum sizes are respected.
- [ ] The UI conforms to the current
      [trend document](../frontend-ui-trend/index.md), and the app's
      [identity](../../domain/identity.md) assets are present and applied:
      palette on both themes, branded loader, favicon, app icon and OG set,
      logo in header, splash, and auth screens.

---

## Related

- [UX patterns](./patterns.md) — the five canonical recipes (search bar, page,
  protected page, onboarding-gated app, form) with their template code paths.
- [Frontend UI trend](../frontend-ui-trend/index.md) — the dated visual pick.
- [Identity](../../domain/identity.md) — the per-app palette, UI language, and
  voice.
- [Next.js baseline](../../developer/nextjs-baseline.md) — the template
  maintenance boundary and deploy rails.
