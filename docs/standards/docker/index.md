# Docker

Docker conventions for containerized builds and deployments. Dockerfiles live under
`infra/`, and there may be several — each one is its own image with its own build
task and its own caller job.

## Local development

Local work uses Taskfile one-liners (these never call the CI scripts). The
authoritative list is `tasks/Taskfile.docker.yaml`: it holds one `build:`, `run:`,
and `clean:` task per Dockerfile, keyed by the Dockerfile's own name — bare
`infra/Dockerfile` is `main`, `infra/<name>.Dockerfile` is `<name>`. Read the task
`desc` to see which Dockerfile a task builds, or run `task --list`.

Pass an optional tag **suffix** after `--`; it is appended to the `:local` tag:

```bash
task docker:build:main            # -> diene-go-base:local
task docker:build:main -- 1       # -> diene-go-base:local-1
task docker:build:main -- hello   # -> diene-go-base:local-hello
```

`run` and `clean` take the same suffix so they act on the image you built.

Adding a Dockerfile means adding its own task set under its own key. Never
generalize the existing tasks into one `build` that switches on a shared image
variable.

## CI/CD release structure

Publishing is driven by the `⚡reusable-docker.yaml` reusable workflow, called from `ci.yaml`
(every commit) and `cd.yaml` (release tag):

1. The reusable workflow sets up the builder with `AtomiCloud/actions.setup-docker` — a
   Namespace (nscloud) backed buildx builder with managed layer caching, so you do **not**
   manage the cache yourself.
2. It runs [`./scripts/ci/docker.sh`](../../../scripts/ci/docker.sh), which reads its build
   and publish settings from the environment the reusable workflow sets. That script owns the
   tag set and the destination: read its `image_id` assignment for where images land, and the
   `-t` arguments on its `buildx build` line for which tags a commit build versus a release
   tag pushes.

   A release build is effectively a re-tag rather than a rebuild, because the buildx cache is
   already warm from the commit build.

### Adding more images

Each image is one caller job — there is **no cap**. Add a job to both `ci.yaml`
and `cd.yaml`, pointing `dockerfile` at a real file owned by that descendant:

```yaml
jobs:
  api:
    uses: ./.github/workflows/⚡reusable-docker.yaml
    secrets: inherit
    with:
      image_name: api
      dockerfile: ./infra/<image>.Dockerfile
      version: ${{ github.ref_name }} # cd.yaml only
```

### Configuration

The reusable workflow's inputs are declared in its own `on.workflow_call.inputs`
block in [`.github/workflows/⚡reusable-docker.yaml`](../../../.github/workflows/⚡reusable-docker.yaml).
Read that block for the current set: each entry names the input, whether it is
`required`, and its `default`. Anything without a default and marked
`required: true` must be supplied by every caller job.

## Linting

Dockerfile linting is not registered as a repository gate. The hooks that do run
are declared in `nix/pre-commit.nix` — see
[the linting standard](../linting/index.md) for how to read them.
