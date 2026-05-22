{
  lib,
  pkgs,
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
  };

  home.sessionVariables."OPENCODE_DISABLE_LSP_DOWNLOAD" = "true";
}
