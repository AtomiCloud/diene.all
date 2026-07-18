# Functional practices in Go

Return `(T, error)` for fallible operations and handle every error explicitly.
Keep transformations deterministic, avoid hidden package state, and pass clocks,
randomness, filesystems, and network clients through interfaces. Wrap errors only
when the added context changes what a caller can understand or do.
