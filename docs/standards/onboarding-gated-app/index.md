---
id: onboarding-gated-app
title: Onboarding-Gated App Pattern
---

# Onboarding-gated app pattern

Every sign-in verifies the home claim before probing the current user. A known
user proceeds; an absent user synchronizes once; recoverable failures remain
retryable. Single-region pass-through still performs the claim check.

See the [Flutter variant](languages/dart.md).
