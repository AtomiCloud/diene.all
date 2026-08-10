# Frontend UI Trend

**This document is DATED and deliberately disposable.** It records the visual
pick in force right now — component vocabulary, polish, typography, motion — and
nothing else. When the pick ages out, this one document is rewritten and no other
standard moves.

> **Current pick: 2026-07 — shadcn-style base plus Vercel-like polish, on
> Tailwind v4 CSS-variable tokens.**

That distinction matters: [frontend UX](../frontend-ux/index.md) is TIMELESS and
mandatory, this page is a snapshot of taste, and
[identity](../../domain/identity.md) is the per-app flavour layered on top of
both. A trend swap must never require touching the UX checklist. If a proposed
trend change would break a checklist item — contrast floors, target sizes, focus
rings, reduced motion, the emoji ban — the checklist wins and the trend proposal
is wrong.

---

## The pick, in force

### Components

shadcn-style: clean, solid buttons and vendored component SOURCE rather than a
runtime component dependency, which fits the template philosophy — the app owns
the code it renders. The template's rule-defaulting components under
`src/components/ui/` are authored in this idiom.

### Icons

ONE icon set per app — currently `lucide-react`, a single stroke weight, sized to
the type scale. Never mixed sets. Never emoji as icons.

### Polish (Vercel-like)

- Dark-mode-comfortable surfaces; both themes are first-class, neither is an
  afterthought.
- Gradients used PURPOSEFULLY — hero moments, calls to action, brand accents,
  subtle glows. Never under body text, where they would break the contrast
  floors.
- Generous whitespace, crisp borders, subtle depth and shadow.
- ONE consistent border-radius scale: rounded, not bubbly.

### Typography

One display face plus one body face. A consistent type scale. Spacing on a 4/8px
grid.

### Motion

Subtle and fast — roughly 100-200ms, eased — with micro-interactions on hover and
press, always behind `prefers-reduced-motion`.

### Emoji

Banned as UI elements, without exception. Icons come from the icon set; brands
come from real, colored logo assets. Emoji appear only inside user content.

---

## Token mechanism (Tailwind v4)

The pick is expressed as CSS variables, not as hard-coded utility values, so a
trend or identity swap is a token edit rather than a component sweep.

- `src/styles/globals.css` declares the light defaults on `:root`, the dark
  overrides on `.dark`, the safe-area variables, and the reduced-motion reset. It
  then maps each token into Tailwind v4's `@theme` colour space (`--color-*`), so
  utilities like `bg-card` and `ring-ring` resolve through the same variables.
- `src/lib/tokens/index.ts` is the single source the runtime theme applier writes
  from — the same variable names for both themes.
- Runtime theme switching rides those variables through the `theme` module of
  `@atomicloud/diene.frontend-utils`; the no-flash init script runs in the locale
  layout before first paint.

Components therefore reference SEMANTIC tokens (`bg-primary`,
`text-muted-foreground`, `border-border`) and never literal colours. This is what
makes the swap procedure below a small change.

---

## Swap procedure

Swapping the trend is a one-document change plus a mechanical token pass. It is
NOT a redesign of the UX rules and NOT an identity change.

1. **Propose.** Write the new pick as a diff against this page: components,
   icons, polish, typography, motion. State the date.
2. **Check against the timeless layer.** Walk
   [the UX checklist](../frontend-ux/index.md) and confirm no item regresses —
   especially contrast floors, 44-48px targets, visible focus rings,
   `prefers-reduced-motion`, CLS-safe sizing, and the emoji ban. A conflict means
   the proposal changes, not the checklist.
3. **Check against identity.** The app's palette, logo, and voice
   ([identity](../../domain/identity.md)) survive the swap. A trend re-tints
   ROLES, it never reassigns brand colours.
4. **Rewrite this page.** Replace the "current pick" block and the sections under
   it. Update the date in the pick line. Do not accumulate a history of past
   picks here — git holds that.
5. **Land the token pass.** Update `src/styles/globals.css` and
   `src/lib/tokens/index.ts`, plus the component idiom under
   `src/components/ui/` where the vocabulary actually changed.
6. **Run the vision loop.** The `vision-loop` skill across representative
   viewports in BOTH themes, and re-run `frontend-ux-check`. Review is the gate;
   there are no golden images.

---

## Related

- [Frontend UX](../frontend-ux/index.md) — the timeless checklist that outranks
  this page.
- [UX patterns](../frontend-ux/patterns.md) — the five canonical recipes.
- [Identity](../../domain/identity.md) — the per-app palette, UI language, and
  voice.
