{ pkgs, packages }:
with packages;
{
  dev = [
    git
    gitlint
    go-task
    helm-schema
    infisical
    releaser
    # scripts/local/latest-chart-upstreams.sh reads the upstream chart and image
    # tags out of the registry with skopeo. Node-owned, so it survives the
    # parent's trim of the shared toolchain.
    skopeo
  ];

  lint = [
    actionlint
    dlint
    gitlint
    helm-schema
    infralint
    pre-commit
    shellcheck
    skills-sync
    treefmt
  ];

  main = [
    cyanprint
    git
    go-task
    infisical
    shellcheck
    # scripts/ci/helm-wrapper.sh runs the wrapper validation tiers in `.#ci` and
    # those arms invoke these directly, not through the validator-runtime in
    # nix/pre-commit.nix.
    kubeconform
    kyverno
    ripgrep
    yq-go
  ];

  releaser = [
    releaser
    # release.hooks.prepare stamps chart/Chart.yaml with yq and regenerates
    # chart/README.md with helm-docs (infralint); the release runs in `.#releaser`.
    infralint
    yq-go
  ];

  system = [
    atomiutils
    infrautils
    nix
  ];
}
