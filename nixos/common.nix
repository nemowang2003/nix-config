{
  inputs,
  lib,
  pkgs,
  hostname,
  cfg,
  ...
}: {
  imports = [
    inputs.catppuccin.nixosModules.catppuccin
  ];

  networking.hostName = hostname;

  nix = {
    settings = lib.mkMerge [
      {
        experimental-features = ["nix-command" "flakes"];
        trusted-users = ["root" "@wheel"];
        always-allow-substitutes = true;
        keep-outputs = true;
        keep-derivations = true;
        auto-optimise-store = true;
      }

      (lib.mkIf cfg.domestic {
        substituters = [
          "https://mirrors.tuna.tsinghua.edu.cn/nix-channels/store"
          "https://mirrors.ustc.edu.cn/nix-channels/store"
          "https://cache.nixos.org"
        ];
      })
    ];

    gc = {
      automatic = true;
      dates = "weekly";
      options = "--delete-older-than 7d";
    };
  };

  services.openssh = {
    enable = true;
    settings = {
      PermitRootLogin = "no";
    };
  };

  users.users.${cfg.user} = {
    isNormalUser = true;
    home = "/home/${cfg.user}";
    shell = pkgs.zsh;
    extraGroups = [
      "wheel"
      "networkmanager"
    ];
    openssh.authorizedKeys.keys = [
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIGool/VQtM3LIxS/UJzur+yOvP4jMNES2WezxxlQwvns nemo@Ians-MacBook-Air.local"
    ];
  };

  programs.zsh = {
    enable = true;
    enableBashCompletion = false;
    enableCompletion = false;
    promptInit = "";
  };
}
