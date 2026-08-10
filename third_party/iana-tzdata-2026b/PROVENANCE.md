# Vendored IANA time zone database source — release 2026b

These are the unmodified native source files from the official IANA time zone
database data release, vendored so the package's timezone-identifier allowlist
(`lib/src/iana_zones.dart`) is reproducible from a repository-owned, verifiable
source rather than from any host's `/usr/share/zoneinfo` or a derived
`tzdata.zi`.

## Official source (pinned)

- Release: **2026b**
- Archive: `tzdata2026b.tar.gz`
- URL: <https://data.iana.org/time-zones/releases/tzdata2026b.tar.gz>
- Archive SHA-256:
  `114543d9f19a6bfeb5bca43686aea173d38755a3db1f2eec112647ae92c6f544`

The same archive digest is served by `data.iana.org` and is the fixed-output
hash pinned by this repository's nixpkgs (`tzdata2026b.tar.gz`), so the vendored
inputs are anchored to the official release, not to a host artifact.

## Vendored files

Extracted verbatim from the archive above:

```
tar -xzf tzdata2026b.tar.gz \
  africa antarctica asia australasia europe northamerica southamerica \
  etcetera factory backward version LICENSE
```

`SHA256SUMS` records the SHA-256 of each vendored file; a reviewer can download
the pinned archive, extract, and confirm the digests match byte-for-byte.

## Identifier extraction policy

`tool/gen_iana_zones.dart` derives the allowlist from exactly the zone-defining
files of the standard (non-`backzone`) distribution:

```
africa antarctica asia australasia europe northamerica southamerica
etcetera factory backward
```

The identifier set is the union of every `Zone <name>` and every
`Link <target> <link-name>` declared in those files (598 identifiers for
2026b). `backzone` is deliberately excluded: it only extends the pre-1970
history of zones that already exist under these files and introduces no new
identifier, so its exclusion does not change the set while keeping the policy
explicit and host-independent.

The files are public domain (see `LICENSE`).
