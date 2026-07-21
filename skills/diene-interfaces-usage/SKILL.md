---
name: diene-interfaces-usage
description: Use diene_interfaces seams and dependency-light in-memory test helpers in Dart or Flutter code.
---

# diene_interfaces usage

Import `package:diene_interfaces/diene_interfaces.dart`, inject the narrow seam
needed by the component, and handle every fallible call as a `Result`. Do not
wrap expected I/O failures in exceptions.

Use `package:diene_interfaces/test_helper.dart` in consumer tests. Seed
`InMemoryVfs`, enqueue terminal results, or enqueue one-shot Result failures on
the System/logging/metrics fakes. The helper sub-library has no test-framework
or Flutter dependency.

Keep runtime telemetry on the Flutter frontend Faro path. Do not add a Dart OTel
exporter or a trace seam to this package.
