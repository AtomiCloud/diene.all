---
name: write-search-bar
description: Build a search or filter bar whose state lives in the URL — local state updates on every keystroke, the URL mirrors it through a debounced replaceState, and pasting the URL elsewhere restores the same view. Use when adding a search input, a filter row, a sort control, tabs, or pagination.
invocation:
  - write-search-bar
  - search-bar
  - url-state
  - filter-bar
---

# Write a Search Bar (url-bound)

Copy the shape from `src/components/home/SearchBar.tsx` and bind it with
`src/adapters/hooks/useUrlState.ts`. The hook owns the URL; the component owns
nothing. Never `push` per keystroke — debounced `replaceState`, so back and
forward stay meaningful.

Follow the rules in
**[frontend-ux/patterns — Search bar](../../../docs/standards/frontend-ux/patterns.md#search-bar-url-bound)**,
then run [`frontend-ux-check`](../frontend-ux-check/SKILL.md) over the result.
