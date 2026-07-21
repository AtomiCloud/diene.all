{
  pkgs,
  packages,
  env,
  shellHook,
}:
with env;
{
  # ### workspace-cd
  # #### source: workspace
  cd = pkgs.mkShell {
    buildInputs = main ++ system;
    inherit shellHook;
  };

  # ### workspace-ci
  # #### source: workspace
  ci = pkgs.mkShell {
    buildInputs = lint ++ main ++ dart-lib ++ system;
    inherit shellHook;
  };

  # ### nix-root-default
  # #### source: main
  default = pkgs.mkShell {
    buildInputs = system ++ main ++ lint ++ dev ++ dart-lib;
    inherit shellHook;
  };

  # ### workspace-releaser
  # #### source: workspace
  releaser = pkgs.mkShell {
    buildInputs = lint ++ main ++ releaser ++ system;
    inherit shellHook;
  };
}
