{
  description = "Nix Configuration of nemowang2003";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";

    flake-parts.url = "github:hercules-ci/flake-parts";
    flake-parts.inputs.nixpkgs-lib.follows = "nixpkgs";

    haumea.url = "github:nix-community/haumea";
    haumea.inputs.nixpkgs.follows = "nixpkgs";

    pyproject-nix.url = "github:pyproject-nix/pyproject.nix";
    pyproject-nix.inputs.nixpkgs.follows = "nixpkgs";

    uv2nix.url = "github:pyproject-nix/uv2nix";
    uv2nix.inputs.nixpkgs.follows = "nixpkgs";
    uv2nix.inputs.pyproject-nix.follows = "pyproject-nix";

    pyproject-build-systems.url = "github:pyproject-nix/build-system-pkgs";
    pyproject-build-systems.inputs.nixpkgs.follows = "nixpkgs";
    pyproject-build-systems.inputs.pyproject-nix.follows = "pyproject-nix";
    pyproject-build-systems.inputs.uv2nix.follows = "uv2nix";

    determinate.url = "github:DeterminateSystems/determinate";
    determinate.inputs.nixpkgs.follows = "nixpkgs";

    darwin.url = "github:nix-darwin/nix-darwin";
    darwin.inputs.nixpkgs.follows = "nixpkgs";

    nix-homebrew.url = "github:zhaofengli/nix-homebrew";

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

    rust-overlay.url = "github:oxalica/rust-overlay";
    rust-overlay.inputs.nixpkgs.follows = "nixpkgs";

    helix.url = "github:helix-editor/helix";

    llm-agents.url = "github:numtide/llm-agents.nix";

    audio-transcribe.url = "github:nemowang2003/audio-transcribe/v0.2.2";
    audio-transcribe.inputs.nixpkgs.follows = "nixpkgs";
    audio-transcribe.inputs.pyproject-nix.follows = "pyproject-nix";
    audio-transcribe.inputs.uv2nix.follows = "uv2nix";
    audio-transcribe.inputs.pyproject-build-systems.follows = "pyproject-build-systems";

    llama-on-demand.url = "github:nemowang2003/llama-on-demand/v0.1.3";
    llama-on-demand.inputs.nixpkgs.follows = "nixpkgs";
    llama-on-demand.inputs.pyproject-nix.follows = "pyproject-nix";
    llama-on-demand.inputs.uv2nix.follows = "uv2nix";
    llama-on-demand.inputs.pyproject-build-systems.follows = "pyproject-build-systems";

    ja2zh-srt.url = "github:nemowang2003/ja2zh-srt/v0.2.2";
    ja2zh-srt.inputs.nixpkgs.follows = "nixpkgs";
    ja2zh-srt.inputs.pyproject-nix.follows = "pyproject-nix";
    ja2zh-srt.inputs.uv2nix.follows = "uv2nix";
    ja2zh-srt.inputs.pyproject-build-systems.follows = "pyproject-build-systems";
    ja2zh-srt.inputs.audio-transcribe.follows = "audio-transcribe";

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
