{
  lib,
  cfg,
  ...
}: {
  nix-homebrew = {
    enable = true;
    enableRosetta = cfg.arch == "aarch64-darwin";
    user = cfg.user;
    autoMigrate = true;

    mutableTaps = false;

    extraEnv = lib.optionalAttrs cfg.domestic {
      HOMEBREW_API_DOMAIN = "https://mirrors.tuna.tsinghua.edu.cn/homebrew-bottles/api";
      HOMEBREW_BOTTLE_DOMAIN = "https://mirrors.tuna.tsinghua.edu.cn/homebrew-bottles";
    };
  };

  homebrew = {
    enable = true;
    enableZshIntegration = false;

    onActivation = {
      extraFlags = ["--verbose"];
      cleanup = "zap";
    };

    global.autoUpdate = false;

    casks =
      [
        "google-chrome"
        "hammerspoon"
        "iina"
        "iterm2"
        "karabiner-elements"
        "mac-mouse-fix"
        "raycast"
        "tailscale-app"
        "tencent-lemon"
        "the-unarchiver"
      ]
      ++ lib.optionals cfg.domestic ["clash-verge-rev"];
  };
}
