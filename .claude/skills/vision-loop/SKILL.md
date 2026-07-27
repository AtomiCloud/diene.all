---
name: vision-loop
description: Close the visual half of UI work by looking at it — capture the screen across representative viewports in both light and dark themes, feed the images to vision or human review, then fix and repeat. Use after building or restyling a surface, after a trend or token swap, or when asked whether something actually looks good.
invocation:
  - vision-loop
  - visual-review
  - screenshot-review
  - does-this-look-good
---

# Vision Loop

Visual quality is judged by LOOKING at the result, not by asserting on pixels.
Capture the surface across representative viewports — a small phone, a large
phone, a tablet, a desktop — in BOTH themes, then feed the images to vision or
human review, fix what the review finds, and repeat until it is genuinely good.

**There are no golden images and no screenshot gates in this template.** That
decision is deliberate: pixel baselines are brittle, they go stale on every
legitimate restyle, and a green baseline says nothing about whether a screen
looks good. Review is the gate. The only browser-side layout assertion that
survives is the non-pixel overflow check in `tests/e2e/resize-fluid.spec.ts`,
which catches horizontal overflow and clipping rather than comparing images.

Follow the procedure in
**[frontend-ux/ section H](../../../docs/standards/frontend-ux/index.md#h-the-vision-loop)**,
and run [`frontend-ux-check`](../frontend-ux-check/SKILL.md) alongside it — the
checklist covers what a screenshot cannot (focus order, announcements, timing).

Both themes are first-class: a surface that only reads well in light mode has
not passed.
