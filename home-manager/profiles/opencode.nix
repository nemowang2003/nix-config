{
  lib,
  pkgs,
  cfg,
  ...
}: let
  ty = lib.getExe pkgs.ty;
in {
  programs.opencode = {
    enable = true;
    enableMcpIntegration = true;

    settings = {
      autoupdate = false;
      share = "disabled";

      lsp = {
        ty = {
          command = [ty "server"];
          extensions = [".py"];
        };
      };
    };

    package =
      if cfg.platform != "wsl"
      then pkgs.opencode
      else
        pkgs.runCommand pkgs.opencode.name {
          nativeBuildInputs = [pkgs.patchelf];
          inherit (pkgs.opencode) meta;
        }
        ''
          cp -a ${pkgs.opencode} $out
          chmod -R u+w $out
          find $out -type f -exec sed -i "s|${pkgs.opencode}|$out|g" {} +
          patchelf --set-interpreter \
            "$(patchelf --print-interpreter "$out/bin/.opencode-wrapped")" \
            "$out/bin/.opencode-wrapped"
        '';
  };

  home.sessionVariables."OPENCODE_DISABLE_LSP_DOWNLOAD" = "true";
}
