{
  self,
  inputs,
  lib,
  pkgs,
  hostname,
  cfg,
  ...
}: {
  imports = [
    inputs.catppuccin.nixosModules.catppuccin
    ./platforms/${cfg.platform}
  ];

  config = lib.mkMerge [
    (self.build-nix-settings cfg)
    {
      catppuccin = {
        enable = true;
        autoEnable = true;
        flavor = "mocha";
      };

      networking.hostName = hostname;

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
        openssh.authorizedKeys.keys = self.user-pubkeys;
      };

      programs = {
        nix-ld.enable = true;

        zsh = {
          enable = true;
          enableBashCompletion = false;
          enableCompletion = false;
          promptInit = "";
        };
      };
    }
  ];
}
