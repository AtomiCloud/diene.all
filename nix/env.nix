{ pkgs, packages }:
with packages;
{
  dev = [
    git
    go-task
    infisical
    releaser
  ];

  lint = [
    actionlint
    dlint
    infralint
    pre-commit
    shellcheck
    skills-sync
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
    shellcheck

    go
    gotestsum
    govulncheck

    # ### operator-template-main
    # #### source: operator-template
    bun
    controller-gen
    kubebuilder
    setup-envtest
  ];

  releaser = [
    releaser
  ];

  system = [
    atomiutils
    infrautils
    nix
  ];
}
