{
  description = "Nix Configuration of nemowang2003";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";

    home-manager.url = "github:nix-community/home-manager";
    home-manager.inputs.nixpkgs.follows = "nixpkgs";

    darwin.url = "github:lnl7/nix-darwin";
    darwin.inputs.nixpkgs.follows = "nixpkgs";

    catppuccin.url = "github:catppuccin/nix";

    devshell.url = "github:numtide/devshell";
    devshell.inputs.nixpkgs.follows = "nixpkgs";
  };

  outputs = { self, nixpkgs, home-manager, darwin, catppuccin, devshell, ... }@inputs: {
    nixosConfigurations = {
      "ian-linuxdesktop" = nixpkgs.lib.nixosSystem {
        specialArgs = { inherit inputs; };
        modules = [
          ./hosts/Ian-LinuxDesktop/system.nix
          catppuccin.nixosModules.catppuccin
        ];
      };

      "ian-windowsdesktop" = nixpkgs.lib.nixosSystem {
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
          ./hosts/ian-macbook/system.nix
        ];
      };
    };

    homeConfigurations = {
      "nemo@ian-macbook" = home-manager.lib.homeManagerConfiguration {
        pkgs = nixpkgs.legacyPackages."aarch64-darwin";
        extraSpecialArgs = { inherit inputs; };
        modules = [
          ./home-manager/basic.nix
          ./home-manager/python.nix
          ./hosts/ian-macbook/home.nix
          catppuccin.homeModules.catppuccin
        ];
      };

      "nemo@ian-linuxdesktop" = home-manager.lib.homeManagerConfiguration {
        pkgs = nixpkgs.legacyPackages."x86_64-linux";
        extraSpecialArgs = { inherit inputs; };
        modules = [
          ./home-manager/basic.nix
          ./hosts/linux-desktop/home.nix
          catppuccin.homeModules.catppuccin
        ];
      };

      "nemo@ian-windowsdesktop" = home-manager.lib.homeManagerConfiguration {
        pkgs = nixpkgs.legacyPackages."x86_64-linux";
        extraSpecialArgs = { inherit inputs; };
        modules = [
          ./home-manager/basic.nix
          ./hosts/windows-desktop/home.nix
          catppuccin.homeModules.catppuccin
        ];
      };

      # TODO: generic linux
      # modules = [
      #   { targets.genericLinux.enable = true; }
      #   ./home-manager/basic.nix
      #   ./hosts/linux/home.nix
      #   catppuccin.homeModules.catppuccin
      # ];
    };

    devShells = let 
      mkOverlay = system: import nixpkgs {
        inherit system;
        overlays = [ devshell.overlays.default ];
      };
    in {
      "aarch64-darwin".default = (mkOverlay "aarch64-darwin").devshell.mkShell {
        _module.args = { inherit inputs; };
        imports = [ ./devshell ];
      };

      "x86_64-linux".default = (mkOverlay "x86_64-linux").devshell.mkShell {
        _module.args = { inherit inputs; };
        imports = [ ./devshell ];
      };
    };
  };
}
