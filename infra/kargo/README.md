# Mercury promotion contract

These resources are reference inputs for the fleet-owned Kargo compiler. The
Mercury repository publishes artifacts but never applies these resources and
contains no direct deployment command.

Kargo creates freight only when the image, app chart, and primordial chart have
the same strict semver. Promotion is ordered `canary` then `active`; each stage
updates the immutable pin in the fleet repository, where Argo CD owns rollout.
