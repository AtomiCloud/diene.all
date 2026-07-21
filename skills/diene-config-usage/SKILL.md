---
name: diene-config-usage
description: Use when loading or testing layered configuration with diene_config.
---

# diene_config usage

Read `doc/configuration.md` from the installed package before changing
configuration code.

- Compose `ConfigSchema` from engine-exported `ConfigBlock<T>` values and the
  service's own blocks. Never recreate an engine schema in the app.
- Load full base YAML, then one flavor/landscape overlay, then an optional dev
  override. Apply explicitly enumerated `String.fromEnvironment` values last.
- Set a per-app prefix. Use `__` nesting and contiguous indexed list keys; do
  not encode lists as JSON or comma-separated strings.
- Call `landscape()` as an accessor for the `DIENE_LANDSCAPE` store-track
  define. Do not detect landscape from hostnames or runtime state.
- In tests, import `package:diene_config/test_helper.dart`; use fake sources or
  `FakeConfigHarness`, and use `ConfigStubBuilder` so stubs remain schema-valid.
