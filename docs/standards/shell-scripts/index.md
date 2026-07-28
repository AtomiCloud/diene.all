---
id: shell-scripts
title: Shell Script Conventions
---

# Shell Script Conventions

This document describes the conventions for shell scripts in the workspace template.

## Required Header

All scripts must start with:

```bash
#!/usr/bin/env bash
set -euo pipefail
```

**Explanation:**

- `#!/usr/bin/env bash` - Use bash via env for portability
- `set -e` - Exit immediately if a command exits with non-zero status (errexit)
- `set -u` - Treat unset variables as an error (nounset)
- `set -o pipefail` - Pipeline fails if any command in it fails

## Style Principles

### Linear and Procedural

- Avoid functions - keep scripts linear and readable
- Execute commands sequentially
- Use comments for section separation

### Prefer Substitution over Flow Control

- Do **not** use flow control (if/else, loops, functions) for simplification or abstraction
- Prefer parameter/command substitution over `if`/`else` — e.g.
  `artifact_version="${version:-v0.0.0-${commit}}"` instead of an `if` block, and
  `arg="$([[ cond ]] && echo "--flag" || echo "")"` for a conditional flag
- Use flow control **only when necessary** (e.g. iterating an unknown number of files)

### Portable and Safe

- Prefer simple, widely-supported Bash syntax; avoid obscure shell features
- Use `$(command)` for command substitution, not backticks
- Write required-variable guards as single-line `[ ] && ... && exit 1` lists
  that report to stderr; keep the guard away from the final line of the script

### Output

- No ANSI color codes, but **prefix every `echo` with a suitable emoji** (🔐 login, 📝 info,
  🔨/📦 build, 📤 push, ✅ success, ❌ failure, …)
- Progress/transition echos are **encouraged** to show what the script is doing — as long as
  they don't clog the script
- Do **not** emit no-op placeholders like `echo "Completed"`

## Template

```bash
#!/usr/bin/env bash
set -euo pipefail

[ -z "${SOME_VAR:-}" ] && echo "❌ 'SOME_VAR' env var not set" >&2 && exit 1

echo "🔨 Doing the thing..."
# commands here

echo "✅ Done"
```

## File Location

All shell scripts live in `scripts/` at the project root. GitHub workflows invoke
`scripts/ci/*` directly; Taskfiles may invoke `scripts/local/*` but never CI
scripts.

```
scripts/
├── ci/
│   ├── setup.sh          # CI setup stub
│   ├── pre-commit.sh     # Pre-commit hooks
│   └── release.sh        # Release process
├── local/                # Developer-facing helpers
├── release/              # Release-time helpers
└── validate/             # Repository-owned policy checks
```

## Summary

| Aspect       | Pattern                                               |
| ------------ | ----------------------------------------------------- |
| **Header**   | `#!/usr/bin/env bash` + `set -euo pipefail`           |
| **Style**    | Linear, portable Bash; substitution over flow control |
| **Progress** | Emoji-prefixed progress echos (no ANSI colors)        |
| **Location** | `scripts/` directory                                  |
