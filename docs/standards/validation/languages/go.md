# Validation in Go

Parse external values into typed domain values at the boundary and return
descriptive errors immediately. Keep transport-shape validation in adapters and
domain invariants in domain constructors or services. Do not pass partially
validated maps or strings deeper into the application.
