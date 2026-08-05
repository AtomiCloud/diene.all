# Commands

Run `task --list` for every available task and its description. The task set is
declared in [`Taskfile.yaml`](Taskfile.yaml), whose `includes:` block maps each
namespace to a file under [`tasks/`](tasks); a task shown as `<namespace>:<task>`
is that key in the included file. Build artifacts — Dockerfiles and Helm charts —
live under [`infra/`](infra) and may be plural, so their tasks are keyed per
artifact. See [the Taskfile standard](docs/standards/taskfile/index.md) for the
conventions.

# Development environment

Diene's reproducible development environment is managed by Nix. Run `direnv allow` once, then use `task` tasks from the loaded shell.

# Standards

[`CLAUDE.md`](CLAUDE.md) is the index of repository conventions: one section per
surface, each pointing at its standard under
[`docs/standards/`](docs/standards). Read the section for the surface you are
changing before you change it.

# Workspace baseline

This tree is the all-features workspace baseline inherited by every downstream sample: split CI/CD, Docker, Helm, secrets, release configuration, validators, standards, and vendored agent-skill synchronization.
