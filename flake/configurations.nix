{
  self,
  inputs,
  lib,
  getSystem,
  ...
}: let
  mkDarwin = hostname: cfg:
    inputs.darwin.lib.darwinSystem {
      system = cfg.arch;
      pkgs = (getSystem cfg.arch).allModuleArgs.pkgs;
      specialArgs = {inherit self inputs hostname cfg;};
      modules = [
        ../darwin
        ../hosts/${hostname}/darwin
      ];
    };

  mkNixOS = hostname: cfg:
    lib.nixosSystem {
      system = cfg.arch;
      pkgs = (getSystem cfg.arch).allModuleArgs.pkgs;
      specialArgs = {inherit self inputs hostname cfg;};
      modules = [
        ../nixos
        ../hosts/${hostname}/nixos
      ];
    };

  mkHome = hostname: cfg:
    inputs.home-manager.lib.homeManagerConfiguration {
      pkgs = (getSystem cfg.arch).allModuleArgs.pkgs;
      extraSpecialArgs = {
        inherit self inputs hostname cfg;
      };
      modules = [
        ../home-manager
        ../hosts/${hostname}/home-manager
      ];
    };
in {
  flake = {
    darwinConfigurations =
      lib.mapAttrs
      (hostname: cfg: mkDarwin hostname cfg)
      (
        lib.filterAttrs
        (hostname: cfg: cfg.is-darwin)
        self.hosts
      );

    nixosConfigurations =
      lib.mapAttrs
      (hostname: cfg: mkNixOS hostname cfg)
      (
        lib.filterAttrs
        (hostname: cfg: cfg.is-linux && cfg.platform != "generic")
        self.hosts
      );

    homeConfigurations =
      lib.mapAttrs'
      (
        hostname: cfg:
          lib.nameValuePair
          "${cfg.user}@${hostname}"
          (mkHome hostname cfg)
      )
      self.hosts;
  };
}
