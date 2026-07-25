#!/usr/bin/env bash
set -euo pipefail

# The restricted pre-commit hook PATH omits go, but scripts/local/skills-sync.sh
# needs it to enumerate dependency skills. Export the absolute go executable so
# the hook honors it via ${DIENE_SKILLS_GO} even under its own PATH.
DIENE_SKILLS_GO="$(command -v go || true)"
export DIENE_SKILLS_GO

./scripts/ci/setup.sh
pre-commit run --all-files --show-diff-on-failure

echo "✅ Pre-commit gates passed"
