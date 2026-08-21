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
        inputs.nix-homebrew.darwinModules.nix-homebrew
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

  mkGeneric = hostname: cfg:
    lib.evalModules {
      specialArgs = {
        inherit self inputs hostname cfg;
        system = cfg.arch;
        pkgs = (getSystem cfg.arch).allModuleArgs.pkgs;
      };
      modules = [
        ../generic
        ../hosts/${hostname}/generic
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
        (hostname: cfg: cfg.isDarwin)
        self.hosts
      );

    nixosConfigurations =
      lib.mapAttrs
      (hostname: cfg: mkNixOS hostname cfg)
      (
        lib.filterAttrs
        (hostname: cfg: cfg.isLinux && cfg.platform != "generic")
        self.hosts
      );

    genericConfigurations =
      lib.mapAttrs
      (hostname: cfg: mkGeneric hostname cfg)
      (
        lib.filterAttrs
        (_: cfg: cfg.platform == "generic")
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
