{
  config,
  pkgs,
  lib,
  ...
}: let
  notify-server-chan = config.my.agent-notify.package;
  agent-languages =
    lib.filterAttrs
    (_: language: language.enable && language.agent.enable)
    config.my.languages;
  agent-lsp-names = lib.unique (lib.concatMap (language: language.lsp) (lib.attrValues agent-languages));
  lsp-servers =
    lib.filterAttrs
    (name: server: lib.elem name agent-lsp-names && server.enable && server.agent.enable)
    config.my.lsp.servers;
  lsp-command = server:
    if server.command != null
    then server.command
    else lib.getExe server.package;
  mk-lsp-mcp-server = server: {
    command = lib.getExe pkgs.mcp-language-server;
    args =
      [
        "-workspace"
        "."
        "-lsp"
        (lsp-command server)
      ]
      ++ lib.optionals (server.args != []) (["--"] ++ server.args);
    enabled = false;
    disabled_tools = [
      "edit_file"
      "rename_symbol"
    ];
    startup_timeout_sec = 20;
    tool_timeout_sec = 120;
  };
in {
  my.env-secrets.DEEPSEEK_API_KEY.group = "common";

  my.codex = {
    enable = true;
    enableMcpIntegration = true;
    package = pkgs.llm-agents.codex;
    context = ./AGENTS.md;
    settings = {
      model = "deepseek-v4-pro";
      model_provider = "deepseek";
      forced_login_method = "api";
      model_reasoning_effort = "max";
      model_catalog_json = ./deepseek-model.json;

      model_providers.deepseek = {
        name = "deepseek";
        base_url = "https://api.deepseek.com/";
        wire_api = "responses";
        env_key = "DEEPSEEK_API_KEY";
      };

      otel.metrics_exporter = "none";
      notify = [(lib.getExe notify-server-chan) "Codex"];

      approval_policy = "never";
      sandbox_mode = "danger-full-access";
      tui.status_line = [
        "model-with-reasoning"
        "current-dir"
        "git-branch"
        "pull-request-number"
        "branch-changes"
        "run-state"
        "permissions"
        "context-remaining"
        "five-hour-limit"
        "weekly-limit"
      ];
      mcp_servers =
        lib.mapAttrs'
        (name: server: lib.nameValuePair "${name}-lsp" (mk-lsp-mcp-server server))
        lsp-servers;
    };
  };
}
