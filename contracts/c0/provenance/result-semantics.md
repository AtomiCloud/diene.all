### §5 Result semantics per language

- TS: async-native `Result<T,E>`/`Option` monad + `ResultSerial` wire form
  (lib/bun/result surface).
- Dart: sealed `Result<T>` (neon seed) aligned to the same combinator names.
- C#: CSharp-Result-style monad (carboxylic.lithium seed), dotnet-idiomatic naming
  (NO TS-parity per LIBS DESIGN) — cross-language table maps equivalence, not
  identical vocabulary.
- Go: **NO monad** — `(T, error)` + problem-typed errors (errors implement the RFC
  9457 problem contract; lib/go/errors-problems).
- Cross-language: combinator name mapping table (map/mapErr/andThen/match ↔ Go
  idioms); error→Problem conversion is the shared semantic anchor.
