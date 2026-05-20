{
  self,
  lib,
  pkgs,
  hostname,
  cfg,
  ...
}: {
  config = lib.mkMerge [
    {
      networking = {
        hostName = hostname;
        localHostName = hostname;
      };

      environment.shells = [pkgs.zsh];

      users.users.${cfg.user} = {
        name = cfg.user;
        home = "/Users/${cfg.user}";
        openssh.authorizedKeys.keys = self.userPubkeys;
      };

      system = {
        primaryUser = cfg.user;
        defaults = {
          # TODO
        };
      };

      programs.zsh = {
        enableBashCompletion = false;
        enableCompletion = false;
        promptInit = "";
      };

      security.pam.services.sudo_local.touchIdAuth = true;

      homebrew = {
        enable = true;
        enableZshIntegration = true;

        onActivation = {
          extraFlags = ["--verbose"];
          cleanup = "zap";
        };

        global.autoUpdate = false;

        casks = [
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
        ];
      };
    }

    (lib.mkIf cfg.domestic {
      environment = {
        etc."nix/nix.custom.conf".text = ''
          substituters = https://mirrors.tuna.tsinghua.edu.cn/nix-channels/store https://mirrors.ustc.edu.cn/nix-channels/store https://cache.nixos.org
        '';
        variables = {
          HOMEBREW_API_DOMAIN = "https://mirrors.tuna.tsinghua.edu.cn/homebrew-bottles/api";
        };
      };
      homebrew.casks = ["clash-verge-rev"];
    })
  ];
}
