# Identity

The per-app flavour layer — Layer 3 of
[the frontend UX doctrine](../standards/frontend-ux/index.md#the-three-layers):
palette, UI language, and voice. Identity is BAKED IN, not decoration: a
recognizable app is identifiable from across the room, on both themes, before a
single word is read.

> **MANDATORY SCAFFOLD STEP — the content below is the SAMPLE identity.**
> A real app MUST replace every section of this document and the token files it
> points at before shipping. **An app cannot ship default-grey.** The sample
> palette is a deliberately opinionated blue-and-amber pick so that "unreplaced"
> is visible rather than invisible — grey defaults would let a product slip out
> the door with no identity at all and nobody noticing.

Replacement checklist for a real app:

- [ ] Palette rewritten in `src/lib/tokens/index.ts` AND `src/styles/globals.css`
      (both themes).
- [ ] Real logo assets committed and referenced from the branding config block.
- [ ] Favicon, app-icon, and OG/social set produced at every density.
- [ ] Branded loader (the Lottie) replaced.
- [ ] Empty-state and failure illustrations drawn in the app's language.
- [ ] Voice and tone section below rewritten, then applied to the locale message
      files.
- [ ] This banner deleted once every box above is checked.

---

## Palette — SAMPLE

Blue primary, amber secondary and accent, in oklch. The authoritative values live
in `src/lib/tokens/index.ts` (the source the runtime theme applier writes from)
and `src/styles/globals.css` (the light defaults plus the `.dark` overrides). Both
themes get the brand — dark is not a desaturated afterthought.

| Role                 | Light                   | Dark                    |
| -------------------- | ----------------------- | ----------------------- |
| `background`         | `oklch(0.985 0.008 84)` | `oklch(0.17 0.02 260)`  |
| `foreground`         | `oklch(0.24 0.03 260)`  | `oklch(0.95 0.01 84)`   |
| `card`               | `oklch(1 0 0)`          | `oklch(0.22 0.025 260)` |
| `primary`            | `oklch(0.55 0.16 255)`  | `oklch(0.7 0.14 255)`   |
| `primary-foreground` | `oklch(0.985 0.008 84)` | `oklch(0.17 0.02 260)`  |
| `secondary`          | `oklch(0.92 0.04 84)`   | `oklch(0.3 0.04 260)`   |
| `muted`              | `oklch(0.95 0.015 84)`  | `oklch(0.27 0.03 260)`  |
| `muted-foreground`   | `oklch(0.5 0.02 260)`   | `oklch(0.7 0.02 84)`    |
| `accent`             | `oklch(0.75 0.14 84)`   | `oklch(0.75 0.14 84)`   |
| `destructive`        | `oklch(0.55 0.2 25)`    | `oklch(0.65 0.2 25)`    |
| `border`             | `oklch(0.9 0.015 84)`   | `oklch(0.3 0.03 260)`   |
| `ring`               | `oklch(0.55 0.16 255)`  | `oklch(0.7 0.14 255)`   |

Semantic rules that survive any palette swap:

- `primary` is the DEFAULT PATH, `destructive` is the dangerous one, ghost and
  outline treatments carry the unlikely choice. A new palette re-tints those
  ROLES; it never reassigns them.
- Both themes must clear the contrast floors of
  [section C](../standards/frontend-ux/index.md#c-responsive-and-visual): text
  4.5:1, UI and borders 3:1.
- `ring` is a real focus ring colour at 3:1 against its adjacent surface — never
  removed, never made subtle.

## UI language — SAMPLE

The recognizable signature, on top of the current
[trend pick](../standards/frontend-ui-trend/index.md):

- **Radius:** one rounded scale — `rounded-lg` for controls and inputs,
  `rounded-2xl` for sheets and dialogs, `rounded-md` for skeletons. Rounded, never
  bubbly.
- **Surface:** cards are `bg-card` on `bg-background` with a single crisp
  `border-border` hairline; depth comes from the border and spacing, not heavy
  shadow.
- **Gradient signature:** amber-to-blue, reserved for hero moments and primary
  calls to action. Never behind body text.
- **Control height:** 48px (`h-12`) for inputs and primary buttons, 44px
  (`h-11`) for icon buttons — the 44-48px target band, never the 24px legal
  floor.
- **Icon set:** `lucide-react`, one stroke weight, sized to the type scale.
- **Spacing:** the 4/8px grid; `gap-2` inside a control group, `gap-4` to `gap-8`
  between sections.
- **Emoji:** never a UI element. Icons come from the set, brands from real
  colored logo assets.

## Identity surfaces

Identity is applied to EVERY surface, not just the header. All of these are
config-driven under the `branding` and `seo` blocks (R21 — no hardcoded identity
value survives `scripts/validate/rebrand-static.ts`):

| Surface                | Where it is wired                                                         |
| ---------------------- | ------------------------------------------------------------------------- |
| Logo                   | `branding.logo` — header, splash, auth screens. Real colored asset.       |
| Favicon                | `branding.favicon`, emitted through the locale layout metadata            |
| App icons and manifest | `src/app/api/manifest/route.ts` plus `branding.themeColor`                |
| Splash                 | `branding.splash`                                                         |
| OG and social cards    | `seo.ogImage`, `seo.twitterCard`, per-page titles via `seo.titleTemplate` |
| JSON-LD                | `seo.jsonLdOrganization`, rendered by `src/lib/seo/index.ts`              |
| Branded loader         | `src/components/lottie/CelebrationLottie.tsx` — loading is a brand moment |
| Empty and error states | the state trio of each data view, illustrated in the app's language       |
| Email templates        | wherever the product sends mail, carrying the same identity               |

## Voice and tone — SAMPLE

The sample copy is plain, direct, and second-person. Rewrite this section for a
real product, then apply it to `messages/*.json`.

- **Register:** plain and concrete. Short sentences. No exclamation marks.
- **Person:** address the user as "you"; the product refers to itself by name,
  not "we".
- **Errors:** say what happened and what to do next, in that order. Never blame
  the user, never expose a stack trace as prose — the copyable error struct of
  Tier 3 is where technical detail belongs.
- **Empty states:** what this space is for, then the one action that fills it.
- **Buttons:** verb-first and specific — "Save changes", not "OK"; "Choose home",
  not "Continue".
- **Localization:** every string lives in the locale message files. Labels are
  written assuming 200-300% expansion when translated.

---

## Related

- [Frontend UX](../standards/frontend-ux/index.md) — the timeless checklist,
  including the trend and identity conformance items.
- [Frontend UI trend](../standards/frontend-ui-trend/index.md) — the dated visual
  pick this identity sits on.
- [Next.js baseline](../developer/nextjs-baseline.md) — what the template owns
  versus what the libraries own.
