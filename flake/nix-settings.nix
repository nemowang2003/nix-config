{lib, ...}: let
  use-helix-nightly = cfg: cfg.arch == "x86_64-linux" || cfg.arch == "aarch64-darwin";
  build-settings = cfg: {
    experimental-features = ["nix-command" "flakes"];
    trusted-users = [
      (
        if cfg.isLinux
        then "@wheel"
        else "@admin"
      )
      cfg.user
    ];
    always-allow-substitutes = true;
    keep-outputs = true;
    keep-derivations = true;
    auto-optimise-store = true;
    substituters = lib.mkMerge [
      (lib.optionals cfg.domestic ["https://mirrors.ustc.edu.cn/nix-channels/store"])
      (lib.mkAfter ["https://cache.nixos.org/" "https://nix-community.cachix.org" "https://cache.numtide.com"])
      (lib.mkIf (use-helix-nightly cfg) (lib.mkAfter ["https://helix.cachix.org"]))
    ];
    trusted-public-keys = lib.mkMerge [
      (lib.mkAfter ["cache.nixos.org-1:6NCHdD59X431o0gWypbMrAURkbJ16ZPMQFGspcDShjY=" "nix-community.cachix.org-1:mB9FSh9qf2dCimDSUo8Zy7bkq5CX+/rkCWyvRCYg3Fs=" "niks3.numtide.com-1:DTx8wZduET09hRmMtKdQDxNNthLQETkc/yaX7M4qK0g="])
      (lib.mkIf (use-helix-nightly cfg) (lib.mkAfter ["helix.cachix.org-1:ejp9KQpR1FBI2onstMQ34yogDm4OgU2ru6lIwPvuCVs="]))
    ];
  };
  build-gc = cfg:
    {
      automatic = true;
      options = "--delete-older-than 7d";
    }
    // (
      if (cfg.isDarwin)
      then {
        interval = {
          Weekday = 0;
          Hour = 0;
          Minute = 0;
        };
      }
      else {
        dates = "weekly";
      }
    );
in {
  flake.build-nix-settings = cfg:
    if cfg.platform == "generic"
    then {
      nix = {
        inherit (cfg) determinate;
        settings = build-settings cfg;
      };
    }
    else if cfg.isDarwin && cfg.determinate
    then {
      determinateNix = {
        enable = cfg.determinate;
        customSettings = build-settings cfg;
        determinateNixd.garbageCollector.strategy = "automatic";
      };
    }
    else
      {
        nix = {
          settings = build-settings cfg;
          gc = build-gc cfg;
        };
      }
      // lib.optionalAttrs (cfg.isLinux && cfg.determinate) {
        determinate.enable = cfg.determinate;
      };
}
