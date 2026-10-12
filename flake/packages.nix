{
  inputs,
  self,
  ...
}: {
  perSystem = {pkgs, ...}: {
    packages = inputs.haumea.lib.load {
      src = ../packages;
      inputs = {
        inherit pkgs;
        inherit (inputs) pyproject-nix;
        python-application = self.lib.python-application;
      };
      loader = inputs.haumea.lib.loaders.callPackage;
      transformer = self.lib.haumea.force-shallow-transformer;
    };
  };
}
