{
  description = "Universal Nix Configuration";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";

    home-manager.url = "github:nix-community/home-manager";
    home-manager.inputs.nixpkgs.follows = "nixpkgs";

    darwin.url = "github:lnl7/nix-darwin";
    darwin.inputs.nixpkgs.follows = "nixpkgs";

    catppuccin.url = "github:catppuccin/nix";
  };

  outputs = { self, nixpkgs, home-manager, darwin, catppuccin, ... }@inputs: {

    nixosConfigurations = {
      "Ian-LinuxDesktop" = nixpkgs.lib.nixosSystem {
        specialArgs = { inherit inputs; };
        modules = [
          ./hosts/Ian-LinuxDesktop/system.nix
          catppuccin.nixosModules.catppuccin
        ];
      };

      "Ian-WindowsDesktop" = nixpkgs.lib.nixosSystem {
        specialArgs = { inherit inputs; };
        modules = [
          ./hosts/Ian-WindowsDesktop/system.nix
          catppuccin.nixosModules.catppuccin
        ];
      };
    };

    darwinConfigurations = {
      "ian-macbook" = darwin.lib.darwinSystem {
        specialArgs = { inherit inputs; };
        modules = [
          ./hosts/darwin/system.nix
        ];
      };
    };

    homeConfigurations = {
      
      "nemo@ian-macbook" = home-manager.lib.homeManagerConfiguration {
        pkgs = nixpkgs.legacyPackages."aarch64-darwin";
        extraSpecialArgs = { inherit inputs; };
        modules = [
          ./home-manager/common.nix
          ./hosts/darwin/home.nix
          catppuccin.homeModules.catppuccin
        ];
      };

      "nemo@ian-linuxdesktop" = home-manager.lib.homeManagerConfiguration {
        pkgs = nixpkgs.legacyPackages."x86_64-linux";
        extraSpecialArgs = { inherit inputs; };
        modules = [
          ./home-manager/common.nix
          ./hosts/linux/home.nix
          catppuccin.homeModules.catppuccin
        ];
      };

      "nemo@ian-windowsdesktop" = home-manager.lib.homeManagerConfiguration {
        pkgs = nixpkgs.legacyPackages."x86_64-linux";
        extraSpecialArgs = { inherit inputs; };
        modules = [
          ./home-manager/common.nix
          ./hosts/linux/home.nix
          catppuccin.homeModules.catppuccin
        ];
      };

      # generic linux
      # modules中应有 { targets.genericLinux.enable = true; }
    };

  };
}
