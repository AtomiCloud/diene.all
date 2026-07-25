# Parity fixtures

Test data only. Nothing here is a roster: `garden-render.sh` refuses to read this
directory unless `DIENE_PARITY_FIXTURES=true` is set, so a fixture can never become a
second membership list for a real environment.

- `primordial/` stands in for the Primordial member export named by `sulfoxide/import.yaml`
  until that export is published. It carries the two Primordial-home members Garden needs
  inside a workload instance.
- `negative/` carries the roster faults the doctor must reject. Each file is applied over
  a copy of the real definition set by `scripts/validate/garden-parity.sh`.
