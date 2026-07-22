---
name: diene-dotnet-result-usage
description: Use AtomiCloud.Diene.Result and its FluentAssertions TestHelper in a .NET consumer.
---

# Diene .NET Result usage

Reference `AtomiCloud.Diene.Result` and import `AtomiCloud.Diene.Results`.
Create values with `Result.Ok<T, E>` / `Result.Err<T, E>` (especially when
`T == E`), compose with `Map`, `Then`, and `MapFailure`, and eliminate both
variants with `Match`. Use `Get` only where the programmer-error
`UnwrapException` boundary is intentional. A default-initialized Result or
Option is invalid and fails loudly.

Raw callbacks are captured only when their overload receives an explicit
`ExceptionFilter`; matched exceptions become failures through the supplied
error mapper and unmatched exceptions rethrow. Result-returning callbacks do
not capture exceptions.

Cross a wire only through `ResultSerial<T, E>` or `OptionSerial<T>` and their
System.Text.Json converters. These encode the C0 v1 tuples `['ok', value]`,
`['err', error]`, `['some', value]`, and `['none', null]`. Do not serialize the
in-memory structs directly.

Tests may reference `AtomiCloud.Diene.Result.TestHelper`, import
`AtomiCloud.Diene.Results.TestHelper`, and use `BeOk`, `BeErr`, `BeSome`, and
`BeNone`. When the expected error is a string, use the named form
`BeErr(expected: "...")` to distinguish it from FluentAssertions' reason
overload. TestHelper code is measured through the meta tier, not the unit
ledger.
