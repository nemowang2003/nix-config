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
        inherit (inputs) uv2nix pyproject-nix pyproject-build-systems;
        python-application = self.lib.python-application;
      };
      loader = inputs.haumea.lib.loaders.callPackage;
      transformer = self.lib.haumea.force-shallow-transformer;
    };
  };
}
