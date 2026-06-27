{
  inputs,
  lib,
  ...
}: {
  perSystem = {system, ...}: {
    _module.args.pkgs = import inputs.nixpkgs {
      inherit system;
      config.allowUnfree = true;
      overlays = [
        (final: prev:
          lib.optionalAttrs (lib.elem system ["x86_64-linux" "aarch64-darwin"]) {
            helix = inputs.helix.packages.${system}.default;
          })
      ];
    };
  };
}
