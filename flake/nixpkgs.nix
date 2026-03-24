{inputs, ...}: {
  perSystem = {system, ...}: {
    _module.args.pkgs = import inputs.nixpkgs {
      inherit system;
      config.allowUnfree = true;

      overlays = let
        mkDarwinOverlays = packages: sourceInput: (
          final: prev: let
            sourcePkgs = sourceInput.legacyPackages.${system};
          in
            builtins.listToAttrs (map (name: {
                name = name;
                value =
                  if prev.stdenv.isDarwin
                  then sourcePkgs.${name}
                  else prev.${name};
              })
              packages)
        );
      in [
        # overlays: more ovelays here
      ];
    };
  };
}
