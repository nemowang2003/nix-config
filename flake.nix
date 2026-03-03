{
  description = "Nix Configuration of nemowang2003";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";

    darwin.url = "github:lnl7/nix-darwin";
    darwin.inputs.nixpkgs.follows = "nixpkgs";

    catppuccin.url = "github:catppuccin/nix";
    catppuccin.inputs.nixpkgs.follows = "nixpkgs";

    devshell.url = "github:numtide/devshell";
    devshell.inputs.nixpkgs.follows = "nixpkgs";

    home-manager.url = "github:nix-community/home-manager";
    home-manager.inputs.nixpkgs.follows = "nixpkgs";

    sops-nix.url = "github:Mic92/sops-nix";
    sops-nix.inputs.nixpkgs.follows = "nixpkgs";
  };

  outputs = {
    self,
    nixpkgs,
    home-manager,
    darwin,
    catppuccin,
    devshell,
    ...
  } @ inputs: let
    systems = [
      "aarch64-darwin"
      "x86_64-linux"
      "aarch64-linux"
    ];

    devSystems = [
      "aarch64-darwin"
      "x86_64-linux"
    ];

    overlayedPkgs = let
      overlays = [
        devshell.overlays.default
      ];
    in
      nixpkgs.lib.genAttrs systems (
        system:
          import nixpkgs {
            inherit system overlays;
            config.allowUnfree = true;
          }
      );
  in {
    # TODO
    # nixosConfigurations = {
    #   "ian-linuxdesktop" = nixpkgs.lib.nixosSystem {
    #     specialArgs = { inherit inputs; };
    #     modules = [
    #       ./hosts/linux-desktop/system.nix
    #       catppuccin.nixosModules.catppuccin
    #     ];
    #   };

    #   "ian-windowsdesktop" = nixpkgs.lib.nixosSystem {
    #     specialArgs = { inherit inputs; };
    #     modules = [
    #       ./hosts/windows-desktop/system.nix
    #       catppuccin.nixosModules.catppuccin
    #     ];
    #   };
    # };

    darwinConfigurations = {
      "ian-macbook" = darwin.lib.darwinSystem {
        specialArgs = {inherit inputs;};
        modules = [
          ./hosts/macbook/system.nix
        ];
      };
    };

    homeConfigurations = {
      "nemo@ian-macbook" = home-manager.lib.homeManagerConfiguration {
        pkgs = overlayedPkgs."aarch64-darwin";
        extraSpecialArgs = {inherit inputs;};
        modules = [
          ./home-manager/basic.nix
          ./home-manager/local.nix
          ./hosts/macbook/home.nix
          catppuccin.homeModules.catppuccin
        ];
      };

      # NixOS WSL
      "nemo@dt-w01" = home-manager.lib.homeManagerConfiguration {
        pkgs = overlayedPkgs."x86_64-linux";
        extraSpecialArgs = {inherit inputs;};
        modules = [
          ./home-manager/basic.nix
          ./home-manager/local.nix
          ./hosts/dt-w01/home.nix
          catppuccin.homeModules.catppuccin
        ];
      };

      # (native) NixOS Desktop
      "nemo@dt-l01" = home-manager.lib.homeManagerConfiguration {
        pkgs = overlayedPkgs."x86_64-linux";
        extraSpecialArgs = {inherit inputs;};
        modules = [
          ./home-manager/basic.nix
          ./home-manager/local.nix
          ./hosts/dt-l01/home.nix
          catppuccin.homeModules.catppuccin
        ];
      };

      "nemo@cn-x01" = home-manager.lib.homeManagerConfiguration {
        pkgs = overlayedPkgs."x86_64-linux";
        extraSpecialArgs = {inherit inputs;};
        modules = [
          {targets.genericLinux.enable = true;}
          ./home-manager/basic.nix
          ./home-manager/remote.nix
          ./hosts/cn-x01/home.nix
          catppuccin.homeModules.catppuccin
        ];
      };

      # TODO: generic linux
      # modules = [
      #   { targets.genericLinux.enable = true; }
      #   ./home-manager/basic.nix
      #   ./hosts/.../home.nix
      #   catppuccin.homeModules.catppuccin
      # ];
    };

    devShells = nixpkgs.lib.genAttrs devSystems (devSystem: {
      default = overlayedPkgs.${devSystem}.devshell.mkShell {
        _module.args = {inherit inputs;};
        imports = [./devshell];
      };
    });
  };
}
