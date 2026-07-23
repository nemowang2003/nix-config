{
  config,
  lib,
  pkgs,
  ...
}: let
  lspServers = lib.filterAttrs (_: server: server.enable && server.agent.enable && server.extensions != []) config.my.lsp.servers;
  lspCommand = server:
    if server.command != null
    then server.command
    else lib.getExe server.package;
  lspLanguage = name: server:
    if server.language != null
    then server.language
    else name;
in {
  programs.claude-code = {
    # TODO: re-enable after Claude Code hooks are managed declaratively.
    enable = false;
    enableMcpIntegration = true;
    package = pkgs.llm-agents.claude-code;

    lspServers =
      lib.mapAttrs'
      (name: server:
        lib.nameValuePair (lspLanguage name server) {
          command = lspCommand server;
          args = server.args;
          extensionToLanguage =
            lib.listToAttrs
            (map (extension: lib.nameValuePair extension (lspLanguage name server)) server.extensions);
        })
      lspServers;
  };
}
