{
  config,
  lib,
  pkgs,
  ...
}: let
  agent-languages =
    lib.filterAttrs
    (_: language: language.enable && language.agent.enable && language.extensions != [])
    config.my.languages;
  lsp-command = server:
    if server.command != null
    then server.command
    else lib.getExe server.package;
  primary-lsp = language:
    lib.findFirst
    (name: let
      server = config.my.lsp.servers.${name} or null;
    in
      server != null && server.enable && server.agent.enable)
    null
    language.lsp;
  claude-languages =
    lib.filterAttrs
    (_: language: primary-lsp language != null)
    agent-languages;
in {
  programs.claude-code = {
    # TODO: re-enable after Claude Code hooks are managed declaratively.
    enable = false;
    enableMcpIntegration = true;
    package = pkgs.llm-agents.claude-code;

    lspServers =
      lib.mapAttrs'
      (name: language: let
        server = config.my.lsp.servers.${primary-lsp language};
      in
        lib.nameValuePair name {
          command = lsp-command server;
          args = server.args;
          extensionToLanguage =
            lib.listToAttrs
            (map (extension: lib.nameValuePair extension name) language.extensions);
        })
      claude-languages;
  };
}
