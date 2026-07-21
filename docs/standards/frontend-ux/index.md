---
id: frontend-ux
title: Frontend UX
---

# Frontend UX

Every UI change runs this checklist until each applicable item clears. Visual
review is evidence for judgment, never a pixel-golden gate.

## State and forms

- Put shareable search, filters, and selection in routed query state; forms
  stay out of URLs.
- Persist unfinished forms locally. Clear every field on submit, cancel,
  explicit reset, or deliberate close; restore after accidental dismissal.
- Validate live on change and repeat validation at the service boundary.
  Preserve paste, autofill, and stable field identity.

## Layout and mobile ergonomics

- Review phone, tablet, and wide layouts in light and dark themes. Never allow
  body-level horizontal scroll or clipped translated labels.
- Use logical alignment, locale-aware numbers/dates, safe-area insets, and
  44–48 dp interaction targets.
- Reserve the OS keyboard for free text. Use bottom sheets for selection,
  pickers for dates, and an inline or sheet keypad for amounts and PINs.
- Put primary mobile actions within thumb reach and keep system back gestures
  unobstructed.

## Feedback and failure

- React to every interaction within roughly 100 ms. Async buttons disable,
  retain their label, show an in-button spinner, and cannot double-fire.
- Design loading, empty, and error states for every data view. Debounce content
  loaders, but never the button reaction.
- Use the Problem catalog's `recoverable` classification: retryable failures
  stay inline; service failures explain the next action; fatal failures get a
  full surface with copyable diagnostic data.
- Execute reversible destructive actions immediately with undo. Reserve
  confirmation dialogs for irreversible actions.

## Accessibility and review

- Keep focus visible, keyboard operation complete, contrast WCAG 2.2-ready,
  and motion removable through the platform reduced-motion setting.
- Run the vision loop at representative sizes and both themes: render, inspect,
  correct, repeat. Screenshots are review inputs, not committed baselines.
- Use one coherent icon family and real colored brand assets. Emoji are user
  content, never interface chrome.

See the [Dart and Flutter variant](languages/dart.md).
