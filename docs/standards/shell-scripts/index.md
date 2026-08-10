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
  `HELM_VERSION="${version:-v0.0.0-${commit}}"` instead of an `if` block, and
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

All shell scripts live in `scripts/` at the project root, in a subdirectory that
says who is allowed to call them:

- `scripts/ci/` — CI/CD lane entry points. Only GitHub workflows invoke these; a
  Taskfile must never call one.
- `scripts/local/` — developer-facing helpers. Taskfiles invoke these, and a
  developer may also run one directly.
- `scripts/validate/` — repository-owned policy checks, invoked by pre-commit
  hooks.

List a directory to see which scripts it currently holds; each script's callers
are the workflow, Taskfile, or hook that names it.

## Summary

| Aspect       | Pattern                                               |
| ------------ | ----------------------------------------------------- |
| **Header**   | `#!/usr/bin/env bash` + `set -euo pipefail`           |
| **Style**    | Linear, portable Bash; substitution over flow control |
| **Progress** | Emoji-prefixed progress echos (no ANSI colors)        |
| **Location** | `scripts/` directory                                  |
