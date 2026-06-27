{
  description = "Nix Configuration of nemowang2003";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";

    flake-parts.url = "github:hercules-ci/flake-parts";
    flake-parts.inputs.nixpkgs-lib.follows = "nixpkgs";

    haumea.url = "github:nix-community/haumea";
    haumea.inputs.nixpkgs.follows = "nixpkgs";

    determinate.url = "github:DeterminateSystems/determinate";
    determinate.inputs.nixpkgs.follows = "nixpkgs";

    darwin.url = "github:nix-darwin/nix-darwin";
    darwin.inputs.nixpkgs.follows = "nixpkgs";

    nixos-wsl.url = "github:nix-community/NixOS-WSL";
    nixos-wsl.inputs.nixpkgs.follows = "nixpkgs";

    devshell.url = "github:numtide/devshell";
    devshell.inputs.nixpkgs.follows = "nixpkgs";

    home-manager.url = "github:nix-community/home-manager";
    home-manager.inputs.nixpkgs.follows = "nixpkgs";

    nixago.url = "github:nix-community/nixago";
    nixago.inputs.nixpkgs.follows = "nixpkgs";
    nixago.inputs.flake-utils.follows = "flake-utils";
    nixago.inputs.nixago-exts.follows = "nixago-exts";

    sops-nix.url = "github:Mic92/sops-nix";
    sops-nix.inputs.nixpkgs.follows = "nixpkgs";

    catppuccin.url = "github:catppuccin/nix";
    catppuccin.inputs.nixpkgs.follows = "nixpkgs";

    helix.url = "github:helix-editor/helix";

    # dependencies
    flake-utils.url = "github:numtide/flake-utils";

    nixago-exts.url = "github:nix-community/nixago-extensions";
    nixago-exts.inputs.flake-utils.follows = "flake-utils";
    nixago-exts.inputs.nixago.follows = "nixago";
    nixago-exts.inputs.nixpkgs.follows = "nixpkgs";
  };

  outputs = {...} @ inputs: let
    lib = inputs.haumea.lib.load {
      src = ./lib;
      inputs = {inherit (inputs.nixpkgs) lib;};
      transformer = inputs.haumea.lib.transformers.liftDefault;
    };
  in
    inputs.flake-parts.lib.mkFlake {inherit inputs;} {
      flake = {inherit lib;};
      imports = lib.collect-nix-files ./flake;
    };
}
