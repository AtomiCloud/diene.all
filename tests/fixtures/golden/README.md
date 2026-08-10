# Release-history goldens

The history bundles in this directory are local, immutable captures used to
exercise version and notes calculation without sibling checkouts or network
access. They are created with `git bundle create <fixture> HEAD --tags` from the
named source checkout at its frozen HEAD, then cloned into disposable temporary
directories by tests.

Expected `*-version.txt` and `*-notes.md` files are reviewed output from the
pure version/notes services. Heading/section and inter-section separators retain
the legacy semantic-release three-newline byte layout. Intentional differences
from legacy output are limited to the documented first-release `1.0.0` rule
and stable LF normalization.
