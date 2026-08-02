{ pkgs, packages }:
with packages;
{
  dev = [
    git
    go-task
    infisical
    pls
    sg
    skopeo
  ];

  lint = [
    actionlint
    infralint
    kubeconform
    kyverno
    pre-commit
    ripgrep
    shellcheck
    treefmt

    deadcode
    gofumpt
    golangci-lint
    staticcheck
  ];

  main = [
    cyanprint
    git
    go-task
    infisical
    kubeconform
    kyverno
    pls
    ripgrep
    shellcheck
    skopeo

    go
    gotestsum
    govulncheck
  ];

  # C2: sg is retained only until tools/releaser is published at step 2p.
  releaser = [
    sg
  ];

  system = [
    atomiutils
    infrautils
  ];
}
