# Flutter template maintenance boundary

This repository owns the reusable baseline: toolchain pins, configuration
grammar, generated-client plumbing, session/onboarding policy, common widgets,
flavor packaging, signing doctors, workflows, standards, and probes.

Consumers own product routes, business-domain models, real endpoints and
client IDs, store copy/media, domain capabilities, notification semantics, and
service-specific Problem catalogs. Do not upstream credentials, product data,
or one app's domain behavior into the template.

E4-final work—argon/Faro integration, general deep links, lib/dart swaps,
discovery allowlists, observability add-back, charts, and cascades—is outside
this v1 boundary.
