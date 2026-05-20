{
  lib,
  pkgs,
  ...
}: {
  programs.claude-code = {
    enable = true;
    enableMcpIntegration = true;

    lspServers = {
      python = {
        command = lib.getExe pkgs.ty;
        args = ["server"];
        extensionToLanguage.".py" = "python";
      };
    };
  };
}
