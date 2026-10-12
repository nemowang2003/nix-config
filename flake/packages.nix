{
  inputs,
  self,
  ...
}: {
  perSystem = {pkgs, ...}: {
    packages =
      (inputs.haumea.lib.load {
        src = ../packages;
        inputs = {
          inherit pkgs;
          inherit (inputs) pyproject-nix;
          python-application = self.lib.python-application;
        };
        loader = inputs.haumea.lib.loaders.callPackage;
        transformer = self.lib.haumea.force-shallow-transformer;
      })
      // {
        audio-transcribe = inputs.audio-transcribe.lib.mkPackage {inherit pkgs;};
        llama-on-demand = inputs.llama-on-demand.lib.mkPackage {inherit pkgs;};
        ja2zh-srt = inputs.ja2zh-srt.lib.mkPackage {inherit pkgs;};
      };
  };
}
