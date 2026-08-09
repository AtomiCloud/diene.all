---
id: search-bar
title: Search Bar Pattern
---

# Search bar pattern

A search bar represents shareable state. The current query is encoded in the
route, restored on entry and back navigation, updated without a full reload,
and debounced only before remote work. Empty queries remove the parameter.

See the [Flutter variant](languages/dart.md).
