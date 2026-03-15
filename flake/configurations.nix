{
  inputs,
  lib,
  getSystem,
  hosts,
  ...
}: let
  mkDarwin = hostname: cfg:
    inputs.darwin.lib.darwinSystem {
      system = cfg.arch;
      pkgs = (getSystem cfg.arch).allModuleArgs.pkgs;
      specialArgs = {inherit inputs hostname;};
      modules = [
        {
          networking = {
            hostName = hostname;
            localHostName = hostname;
          };
          system.primaryUser = cfg.user;
          users.users.${cfg.user} = {
            name = cfg.user;
            home = "/Users/${cfg.user}";
          };
        }
        ../hosts/${hostname}/darwin.nix
      ];
    };

  mkNixOS = hostname: cfg:
    lib.nixosSystem {
      system = cfg.arch;
      pkgs = (getSystem cfg.arch).allModuleArgs.pkgs;
      specialArgs = {inherit inputs hostname;};
      modules = [
        {
          users.users.${cfg.user} = {
            isNormalUser = true;
            home = "/home/${cfg.user}";
            extraGroups = [
              "wheel"
              "networkmanager"
            ];
          };
        }
        ../hosts/${hostname}/nixos.nix
        inputs.catppuccin.nixosModules.catppuccin
      ];
    };

  mkHome = hostname: cfg:
    inputs.home-manager.lib.homeManagerConfiguration {
      pkgs = (getSystem cfg.arch).allModuleArgs.pkgs;
      extraSpecialArgs = {inherit inputs;};
      modules = [
        ../home-manager/basic.nix
        ../hosts/${hostname}/home.nix
        inputs.catppuccin.homeModules.catppuccin
        {targets.genericLinux.enable = cfg.generic;}
      ];
    };
in {
  flake = let
    isDarwin = arch: (lib.systems.elaborate arch).isDarwin;
    isLinux = arch: (lib.systems.elaborate arch).isLinux;
  in {
    darwinConfigurations = lib.mapAttrs (
      hostname: cfg:
        mkDarwin hostname cfg
    ) (lib.filterAttrs (hostname: cfg: isDarwin cfg.arch) hosts);
    nixosConfigurations = lib.mapAttrs (
      hostname: cfg:
        mkNixOS hostname cfg
    ) (lib.filterAttrs (hostname: cfg: isLinux cfg.arch && !cfg.generic) hosts);

    homeConfigurations =
      lib.mapAttrs' (
        hostname: cfg:
          lib.nameValuePair "${cfg.user}@${hostname}" (mkHome hostname cfg)
      )
      hosts;
  };
}
