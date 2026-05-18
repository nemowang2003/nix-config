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
      specialArgs = self // {inherit hostname cfg;};
      modules =
        [
          ../darwin/common.nix
          ../hosts/${hostname}/darwin.nix
        ]
        ++ lib.optionals cfg.determinate [../darwin/determinate.nix];
    };

  mkNixOS = hostname: cfg:
    lib.nixosSystem {
      system = cfg.arch;
      pkgs = (getSystem cfg.arch).allModuleArgs.pkgs;
      specialArgs = self // {inherit hostname cfg;};
      modules = [
        ../nixos/${cfg.platform}.nix
        ../nixos/common.nix
        ../hosts/${hostname}/nixos.nix
      ];
    };

  mkHome = hostname: cfg:
    inputs.home-manager.lib.homeManagerConfiguration {
      pkgs = (getSystem cfg.arch).allModuleArgs.pkgs;
      extraSpecialArgs = {inherit hostname cfg;};
      modules = [
        ../home-manager/common.nix
        ../hosts/${hostname}/home.nix
      ];
    };
in {
  flake = {
    darwinConfigurations =
      lib.mapAttrs
      (hostname: cfg: mkDarwin hostname cfg)
      (
        lib.filterAttrs
        (hostname: cfg: self.lib.arch.isDarwin cfg.arch)
        self.hosts
      );

    nixosConfigurations =
      lib.mapAttrs
      (hostname: cfg: mkNixOS hostname cfg)
      (
        lib.filterAttrs
        (hostname: cfg: self.lib.arch.isLinux cfg.arch && cfg.platform != "generic")
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
