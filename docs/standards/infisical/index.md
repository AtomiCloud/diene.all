# Infisical

Secret management with [Infisical](https://secrets.atomi.cloud).

## Usage

Always use the subprocess form with a trailing `-- ` to propagate secrets to the
command:

```bash
infisical run --env=dev -- env | grep MY_SECRET
infisical run --env=dev -- task lint
```

The bare form `infisical run --env=dev` (without `-- <command>`) does **not** propagate
secrets to the parent shell — secrets are only available inside the Infisical subprocess.
This is a common footgun; always include `-- <command>` when you need secrets in your
current shell environment.

## Setup

[`scripts/local/secrets.sh`](../../../scripts/local/secrets.sh) owns the secret
actions. It takes the action as its first argument, and the `case` block near the
top of the script is the authoritative list of the actions it accepts; each branch
also declares, as `[ -z "${VAR:-}" ] && … && exit 1` guards, the environment
variables that action requires.

The task wrappers are in [`tasks/Taskfile.secret.yaml`](../../../tasks/Taskfile.secret.yaml),
included under the `secret` namespace, so each task there is `task secret:<task>`.
Read the file, or run `task --list`, to see which ones exist.

Authentication is not a separate step: the fetch path logs you in when no valid
token is present.
