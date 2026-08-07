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

## Logging in

[`scripts/local/secrets.sh`](../../../scripts/local/secrets.sh) does one thing: it
makes sure this machine has a usable Infisical session, logging in only when there
is not one already. It takes no arguments, writes no files, and is safe to run
again at any time.

```bash
./scripts/local/secrets.sh
```

`INFISICAL_API_URL` selects the instance and defaults to `https://secrets.atomi.cloud`.

There is no task wrapper and no fetch action. Once you have a session, read secrets
with the `infisical run -- <command>` form above rather than exporting them into a
file — a `.env` on disk is a copy of your secrets that nothing keeps current.

## Scanning for committed secrets

Two pre-commit hooks run `infisical scan` on every commit — one over the whole tree
and one over the staged changes. Both pass `--redact`, so a finding reports its file
and line but never the candidate value; these hooks also run in CI, where the value
would otherwise reach a build log. Do not remove `--redact`.
