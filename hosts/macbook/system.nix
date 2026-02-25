{ pkgs, inputs, ... }:

{
  imports = [
    inputs.home-manager.darwinModules.home-manager
  ];

  nix.enable = false;
  nixpkgs.hostPlatform = "aarch64-darwin";

  programs.zsh.enable = true;
  environment = {
    etc."nix/nix.custom.conf".text = ''
      substituters = https://mirrors.tuna.tsinghua.edu.cn/nix-channels/store https://mirrors.ustc.edu.cn/nix-channels/store https://cache.nixos.org
    '';
    shells = [ pkgs.zsh ];
    variables = {
      HOMEBREW_API_DOMAIN = "https://mirrors.tuna.tsinghua.edu.cn/homebrew-bottles/api";
    };
  };

  security.pam.services.sudo_local.touchIdAuth = true;

  system = {
    primaryUser = "nemo";

    activationScripts.postActivation.text = ''
      echo "restarting determinate nix daemon ..."
      launchctl kickstart -k system/systems.determinate.nix-daemon
    '';
  };

  users.users.nemo = {
    name = "nemo";
    home = "/Users/nemo";
    shell = pkgs.zsh;
  };

  homebrew = {
      enable = true;

      onActivation = {
        extraFlags = [ "--verbose" ];
        cleanup = "zap";
      };

      global.autoUpdate = false;

      casks = [
        "android-platform-tools"
        "bitwarden"
        "clash-verge-rev"
        "google-chrome"
        "hammerspoon"
        "iina"
        "iterm2"
        "karabiner-elements"
        "mac-mouse-fix"
        "obsidian"
        "qq"
        "raycast"
        "steam"
        "tailscale-app"
        "tencent-lemon"
        "tencent-meeting"
        "the-unarchiver"
        "visual-studio-code"
        "wechat"
        "windows-app"
        "wpsoffice-cn"
      ];
  };

  system.stateVersion = 6;
}
