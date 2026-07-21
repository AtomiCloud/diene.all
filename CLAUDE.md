# diene_core_utils agent entry

This branch owns only the publishable Dart package `diene_core_utils`.

- Public contract and parity notes: `doc/core_utils.md`
- Public barrel: `lib/diene_core_utils.dart`
- Unit/conformance tests: `test/`
- Installed usage skill: `skills/diene-core-utils-usage/SKILL.md`

Do not add Flutter, I/O, telemetry, or test-framework dependencies to the runtime
package. TestHelper remains opt-in and currently has a NO verdict.
