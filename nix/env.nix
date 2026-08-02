{ pkgs, packages }:
with packages;
{
  dev = [
    git
    gitlint
    go-task
    helm-schema
    infisical
    pls
    sg
    skopeo
  ];

  lint = [
    actionlint
    gitlint
    helm-schema
    infralint
    kubeconform
    kyverno
    pre-commit
    ripgrep
    shellcheck
    treefmt
  ];

  main = [
    pkgs.bun
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

  # C2: sg is retained only until tools/releaser is published at step 2p.
  releaser = [
    sg
  ];

  system = [
    atomiutils
    infrautils
  ];
}
