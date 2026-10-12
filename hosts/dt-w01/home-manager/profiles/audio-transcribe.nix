{
  pkgs,
  self,
  ...
}: {
  home.packages = [
    (self.packages.${pkgs.stdenv.hostPlatform.system}.audio-transcribe.override {cudaSupport = true;})
  ];
}
