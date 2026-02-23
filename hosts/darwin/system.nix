{ pkgs, inputs, ... }:

{
  imports = [
    inputs.home-manager.darwinModules.home-manager
  ];

  nixpkgs.hostPlatform = "aarch64-darwin";

  system.primaryUser = "nemo";
  users.users.nemo = {
    name = "nemo";
    home = "/Users/nemo";
    shell = pkgs.zsh;
  };
  security = {
    pam.services.sudo_local.touchIdAuth = true;
    sudo.extraConfig = ''
      Defaults env_keep += "https_proxy http_proxy all_proxy"
    '';
  };

  environment = {
    shells = [ pkgs.zsh ];
    systemPackages = [
      inputs.darwin.packages."${pkgs.stdenv.hostPlatform.system}".default
    ];  
  };
  nix.enable = false;
  programs.zsh.enable = true;

  homebrew = {
      enable = true;

      onActivation = {
        autoUpdate = true;
        upgrade = true;
        extraFlags = [ "--verbose" ];
        cleanup = "zap";
      };

      global.brewfile = true;
    
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
