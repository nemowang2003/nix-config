{
  self,
  inputs,
  ...
}: {
  perSystem = {pkgs, ...}: {
    packages = inputs.haumea.lib.load {
      src = ../packages;
      inputs = {inherit pkgs;};
      loader = inputs.haumea.lib.loaders.callPackage;
      transformer = self.lib.haumea.force-shallow-transformer;
    };
  };
}
