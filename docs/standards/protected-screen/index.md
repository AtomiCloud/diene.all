---
id: protected-screen
title: Protected Screen Pattern
---

# Protected screen pattern

Authorization is checked before protected content renders. Preserve the full
intended route as `returnTo`, authenticate once, re-check authorization, and
return without losing query state. A denial is distinct from sign-in failure.

See the [Flutter variant](languages/dart.md).
