{
  lib,
  pkgs,
  ...
}: {
  programs.claude-code = {
    # TODO: re-enable after Claude Code hooks are managed declaratively.
    enable = false;
    enableMcpIntegration = true;
    package = pkgs.llm-agents.claude-code;

    lspServers = {
      python = {
        command = lib.getExe pkgs.ty;
        args = ["server"];
        extensionToLanguage.".py" = "python";
      };
    };
  };
}
