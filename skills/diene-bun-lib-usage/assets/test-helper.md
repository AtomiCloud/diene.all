# Adding a TestHelper

Add a dependency-light `./test-helper` export only when consumers repeatedly
need the same fake, builder, or assertion. Keep framework-specific packages in
optional peer dependencies, prove helpers in the meta tier, and keep helper
coverage out of the unit ledger.
