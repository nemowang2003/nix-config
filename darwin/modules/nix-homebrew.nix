{
  self,
  config,
  lib,
  options,
  pkgs,
  ...
}: let
  cfg = config.my.homebrew;
  upstream = options.nix-homebrew;
  mirrored-homebrew-options = self.lib.options.mirror-options {
    inherit upstream;
    # These are derived by nix-homebrew itself rather than user-facing input.
    excluded = ["package" "prefixes" "defaultArm64Prefix" "defaultIntelPrefix"];
  };

  # nix-homebrew evaluates `brew shellenv`, but does not expose Homebrew's own
  # completion from its Nix-managed source tree. Keep this in the system
  # profile rather than mutating the Homebrew prefix with `brew completions`.
  brew-completions = pkgs.runCommand "brew-completions" {} ''
    mkdir -p "$out/share/zsh/site-functions"
    ln -s ${config.nix-homebrew.package}/completions/zsh/_brew \
      "$out/share/zsh/site-functions/_brew"
  '';
in {
  options.my.homebrew =
    mirrored-homebrew-options
    // {
      completions.enable = lib.mkEnableOption "Homebrew's Nix-managed shell completions";
    };

  config = lib.mkIf cfg.enable {
    nix-homebrew = removeAttrs cfg ["completions"];

    environment.systemPackages = lib.optional cfg.completions.enable brew-completions;
  };
}
