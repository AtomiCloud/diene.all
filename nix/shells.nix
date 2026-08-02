{
  pkgs,
  packages,
  env,
  shellHook,
}:
with env;
{
  # infralint ships helm-docs, which scripts/ci/publish.sh regenerates chart/README.md with.
  cd = pkgs.mkShell {
    buildInputs = main ++ system ++ [ packages.infralint ];
    inherit shellHook;
  };

  ci = pkgs.mkShell {
    buildInputs = lint ++ main ++ system;
    inherit shellHook;
  };

  default = pkgs.mkShell {
    buildInputs = system ++ main ++ lint ++ dev;
    inherit shellHook;
  };

  releaser = pkgs.mkShell {
    buildInputs = lint ++ main ++ releaser ++ system;
    inherit shellHook;
  };
}
