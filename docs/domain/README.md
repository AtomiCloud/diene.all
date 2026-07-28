# Domain documentation

Domain-specific architecture and behavior belongs under `docs/domain/`. Workspace owns only this layout convention; descendants add their own domain documents in keyed, source-attributed sections.

<!-- ### dotnet-server-engine -->
<!-- #### source: lib/dotnet/server-engine -->

- [Server engine](server-engine.md) — the MVC base, the exception-to-Problem
  filter, the system routes, OnboardSync, and the signed webhook receiver.
