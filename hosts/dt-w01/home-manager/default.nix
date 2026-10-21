{
  pkgs,
  inputs,
  lib,
  self,
  ...
}: let
  windows-path = lib.getExe self.packages.${pkgs.stdenv.hostPlatform.system}.wsl-windows-path;
in {
  imports = self.lib.collect-nix-files ./profiles;

  home.stateVersion = "25.11";

  home.packages = [
    (inputs.audio-transcribe.lib.mkPackage {
      inherit pkgs;
      cudaSupport = true;
    })
    (inputs.ja2zh-srt.lib.mkPackage {
      inherit pkgs;
      cudaSupport = true;
    })
  ];

  # zshenv covers interactive SSH shells and non-interactive SSH commands.
  # Child shells inherit the resolved PATH without querying Windows again.
  programs.zsh.envExtra = lib.mkAfter ''
    if [[ -z "''${NIX_CONFIG_WINDOWS_PATH_READY-}" ]]; then
      export PATH="$PATH$(${windows-path})"
      export NIX_CONFIG_WINDOWS_PATH_READY=1
    fi
  '';
}
