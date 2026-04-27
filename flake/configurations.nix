{
  self,
  inputs,
  lib,
  getSystem,
  ...
}: let
  userPubkeys =
    lib.mapAttrsToList
    (hostname: cfg: cfg.userPubkey)
    (lib.filterAttrs (hostname: cfg: cfg.userPubkey != null) self.hosts);

  mkDarwin = hostname: cfg:
    inputs.darwin.lib.darwinSystem {
      system = cfg.arch;
      pkgs = (getSystem cfg.arch).allModuleArgs.pkgs;
      specialArgs = {inherit inputs hostname cfg userPubkeys;};
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
      specialArgs = {inherit inputs hostname cfg userPubkeys;};
      modules = [
        ../nixos/${cfg.platform}.nix
        ../nixos/common.nix
        ../hosts/${hostname}/nixos.nix
      ];
    };

  mkHome = hostname: cfg:
    inputs.home-manager.lib.homeManagerConfiguration {
      pkgs = (getSystem cfg.arch).allModuleArgs.pkgs;
      extraSpecialArgs = {inherit inputs hostname cfg userPubkeys;};
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
