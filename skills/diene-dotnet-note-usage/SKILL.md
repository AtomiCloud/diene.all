---
name: diene-dotnet-note-usage
description: Use AtomiCloud.Diene.Note and its TestHelper assertions in a .NET consumer.
---

# Diene .NET Note usage

Use `NoteRecord` for immutable note content, `NotePrincipal` for persisted
identity plus content, and inject `INoteSummariser` or `INoteRepository` at
consumer boundaries. Do not copy the implementation or hide failures in a
service locator.

Tests may reference `AtomiCloud.Diene.Note.TestHelper` and call
`NoteAssertions.AssertSummary`. Exercise a known-good and known-bad assertion
case when extending the helper. The TestHelper assembly is test infrastructure:
measure it through the meta tier, never the unit ledger.

For package lifecycle, identity, coverage, and promotion rules, read
`docs/developer/dotnet-lib-baseline.md` in the source repository.
