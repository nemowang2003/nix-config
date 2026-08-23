{
  config,
  pkgs,
  lib,
  ...
}: let
  codex-notify = pkgs.nemowang2003.codex-notify;
  codex-notify-min-duration = "300";
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
  # SERVERCHAN_SEND_URL is the bare ServerChan³ send endpoint; codex-notify
  # POSTs title/desp to it. See packages/serverchan-notify.nix.
  my.env-secrets.SERVERCHAN_SEND_URL.group = "common";

  home.shellAliases."codex-list-sessions" = ''
    ${lib.getExe pkgs.sqlite} -readonly -header -column "${config.home.homeDirectory}/.codex/state_5.sqlite" \
      "SELECT id, cwd, title FROM threads ORDER BY updated_at DESC;" | $EDITOR
  '';

  my.codex = {
    enable = true;
    enableMcpIntegration = true;
    package = pkgs.llm-agents.codex;
    contexts = [./AGENTS.md];
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
      notify = [(lib.getExe codex-notify) "Codex" codex-notify-min-duration];

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

    # Track each session's start so codex-notify can tell short turns from
    # long tasks. Only startup/resume/clear reset the marker; compaction in
    # the middle of a turn must not truncate the measured duration.
    hooks = {
      SessionStart = [
        {
          matcher = "^(startup|resume|clear)$";
          hooks = [
            {
              type = "command";
              command = "${lib.getExe codex-notify} start";
              timeout = 3;
            }
          ];
        }
      ];
    };
  };
}
