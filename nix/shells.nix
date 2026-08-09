{
  pkgs,
  packages,
  env,
  shellHook,
}:
with env;
{
  cd = pkgs.mkShell {
    buildInputs = main ++ system;
    inherit shellHook;
  };

  ci = pkgs.mkShell {
    buildInputs = lint ++ main ++ system;
    inherit shellHook;
  };

  default = pkgs.mkShell {
    buildInputs = system ++ main ++ lint ++ dev ++ releaser;
    inherit shellHook;
  };

  releaser = pkgs.mkShell {
    buildInputs = lint ++ main ++ releaser ++ system;
    inherit shellHook;
  };
}
