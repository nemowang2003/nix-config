{
  lib,
  pkgs,
  ...
}: let
  pkg = pkgs.llm-agents.opencode;
  # Keep opencode-only runtime flags out of the global session environment.
  opencode = pkgs.writeShellApplication {
    name = "opencode";
    text = ''
      export OPENCODE_DISABLE_LSP_DOWNLOAD=true
      export OPENCODE_EXPERIMENTAL_LSP_TOOL=true
      export OPENCODE_EXPERIMENTAL_LSP_TY=true

      exec ${lib.getExe pkg} "$@"
    '';
  };
in {
  programs.opencode = {
    enable = true;
    enableMcpIntegration = true;

    settings = {
      autoupdate = false;
      share = "disabled";
      permission = "allow";

      provider = {
        deepseek.options.chunkTimeout = 300000;
      };

      lsp = true;
    };

    package = opencode;
  };
}
