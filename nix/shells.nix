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

  # ### flutter-base-cd-ios
  # #### source: flutter-base
  cd-ios = pkgs.mkShell {
    buildInputs = mobile ++ system ++ [ packages.ruby-xcodeproj ];
    inherit shellHook;
  };

  # ### flutter-base-cd-android
  # #### source: flutter-base
  cd-android = pkgs.mkShell {
    buildInputs = mobile ++ android ++ system;
    inherit shellHook;
    ANDROID_SDK_ROOT = "${packages.androidsdk}/libexec/android-sdk";
    ANDROID_HOME = "${packages.androidsdk}/libexec/android-sdk";
    JAVA_HOME = "${packages.jdk17.home}";
  };

  # ### workspace-ci
  # #### source: workspace
  ci = pkgs.mkShell {
    buildInputs = lint ++ main ++ mobile ++ system;
    inherit shellHook;
  };

  # ### nix-root-default
  # #### source: main
  default = pkgs.mkShell {
    buildInputs = system ++ main ++ lint ++ dev ++ mobile ++ android;
    inherit shellHook;
    ANDROID_SDK_ROOT = "${packages.androidsdk}/libexec/android-sdk";
    ANDROID_HOME = "${packages.androidsdk}/libexec/android-sdk";
    JAVA_HOME = "${packages.jdk17.home}";
  };

  # ### workspace-releaser
  # #### source: workspace
  releaser = pkgs.mkShell {
    buildInputs = lint ++ main ++ releaser ++ system;
    inherit shellHook;
  };
}
