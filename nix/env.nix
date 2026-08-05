{ pkgs, packages }:
with packages;
{
  dev = [
    git
    go-task
    infisical
    releaser
    skopeo
  ];

  lint = [
    actionlint
    infralint
    pre-commit
    shellcheck
    treefmt
  ];

  main = [
    cyanprint
    git
    go-task
    infisical
    shellcheck
    skopeo
  ];

  # The releaser is the release toolchain now that it is available here, so this
  # group holds the real binary and the temporary gitlint bootstrap that stood in
  # for it is gone from the workspace entirely. That binary's own name is
  # deliberately not written in this file: binary smoke refuses if it appears
  # here, so the removal is explained beside the guard instead.
  #
  # It is declared HERE and in `dev`, and deliberately not in `main`. `dev` backs
  # only the default shell, which is where a developer runs `releaser next` or
  # `releaser conventions` by hand and where binary smoke exercises it. `main`
  # backs `cd` and `ci`, and no CI or CD job outside the release path invokes the
  # tool, so putting it there would carry a release-authoring binary into the
  # deploy shell for nothing. `dev` and this group never appear in the same shell
  # (`default` takes `dev`, `releaser` takes this one), so nothing is declared
  # twice - which matters because `mkShell` would silently order a duplicate
  # rather than refuse it.
  releaser = [
    releaser
  ];

  system = [
    atomiutils
    infrautils
  ];
}
