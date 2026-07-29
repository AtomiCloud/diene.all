{ pkgs, packages }:
with packages;
{
  # ### workspace-dev
  # #### source: workspace
  dev = [
    git
    go-task
    infisical
    pls
    sg
    skopeo
  ];

  # ### workspace-lint
  # #### source: workspace
  lint = [
    actionlint
    infralint
    kubeconform
    kyverno
    pre-commit
    ripgrep
    shellcheck
    treefmt
  ];

  # ### workspace-main
  # #### source: workspace
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
  ];

  # ### workspace-releaser-bootstrap
  # #### source: workspace
  # C2: sg is retained only until tools/releaser is published at step 2p.
  releaser = [
    sg
  ];

  # ### nix-root-system
  # #### source: main
  system = [
    atomiutils
    infrautils
  ];
}
