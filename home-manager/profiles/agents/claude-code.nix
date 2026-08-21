{
  config,
  lib,
  pkgs,
  ...
}: let
  agentLanguages =
    lib.filterAttrs
    (_: language: language.enable && language.agent.enable && language.extensions != [])
    config.my.languages;
  lspCommand = server:
    if server.command != null
    then server.command
    else lib.getExe server.package;
  primaryLsp = language:
    lib.findFirst
    (name: let
      server = config.my.lsp.servers.${name} or null;
    in
      server != null && server.enable && server.agent.enable)
    null
    language.lsp;
  claudeLanguages =
    lib.filterAttrs
    (_: language: primaryLsp language != null)
    agentLanguages;
in {
  programs.claude-code = {
    # TODO: re-enable after Claude Code hooks are managed declaratively.
    enable = false;
    enableMcpIntegration = true;
    package = pkgs.llm-agents.claude-code;

    lspServers =
      lib.mapAttrs'
      (name: language: let
        server = config.my.lsp.servers.${primaryLsp language};
      in
        lib.nameValuePair name {
          command = lspCommand server;
          args = server.args;
          extensionToLanguage =
            lib.listToAttrs
            (map (extension: lib.nameValuePair extension name) language.extensions);
        })
      claudeLanguages;
  };
}
