{
  lib,
  cfg,
  ...
}: {
  homebrew = {
    enable = true;
    enableZshIntegration = true;

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
  environment.variables = lib.mkIf cfg.domestic {
    HOMEBREW_API_DOMAIN = "https://mirrors.tuna.tsinghua.edu.cn/homebrew-bottles/api";
  };
}
