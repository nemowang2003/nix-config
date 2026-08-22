{
  inputs,
  self,
  ...
}: {
  flake.overlays.default = final: prev: {
    nemowang2003 = inputs.haumea.lib.load {
      src = ../packages;
      inputs = {pkgs = final;};
      loader = inputs.haumea.lib.loaders.callPackage;
      transformer = self.lib.haumea.force-shallow-transformer;
    };
  };
}
