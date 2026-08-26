{
  self,
  config,
  pkgs,
  lib,
  cfg,
  ...
}: let
  codex-notify = pkgs.nemowang2003.codex-notify;
  # Only the multitool `codex` binary belongs on PATH; the package also ships
  # codex-code-mode-host and logs_client, which are never invoked by name.
  codex-package = pkgs.symlinkJoin {
    name = "codex";
    paths = [pkgs.llm-agents.codex];
    postBuild = ''
      rm -f "$out/bin/codex-code-mode-host" "$out/bin/logs_client"
    '';
    inherit (pkgs.llm-agents.codex) version;
  };
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
  # Per-person notification routes for codex-notify: a map of profile name to
  # both the ServerChan³ push URL and the WeCom single-chat userid. One thread
  # is bound to one profile with `codex-notify route <thread-id> <name>`;
  # unrouted threads go to `me`.
  my.secrets.files.routes = {
    scope = "common";
    file = "routes.json";
    format = "json";
    path = "${config.xdg.configHome}/codex-notify/routes.json";
    mode = "0600";
  };

  # 企业微信智能机器人凭据 for codex-reply; declared only once the
  # encrypted file exists so hosts still evaluate before the secret is added.
  # Gated on cfg.trusted: non-trusted hosts cannot decrypt the file and must
  # not fail activation trying to materialize it.
  my.secrets.files."wecom" =
    lib.mkIf (
      cfg.trusted && builtins.pathExists (self.sops.dirs.trusted + "/wecom.json")
    ) {
      scope = "trusted";
      file = "wecom.json";
      format = "json";
      path = "${config.xdg.configHome}/codex-reply/wecom.json";
      mode = "0600";
    };

  home.packages = [codex-notify];

  home.shellAliases."codex-list-sessions" = ''
    ${lib.getExe pkgs.sqlite} -readonly -header -column "${config.home.homeDirectory}/.codex/state_5.sqlite" \
      "SELECT id, cwd, title FROM threads ORDER BY updated_at DESC;" | $EDITOR
  '';

  my.codex = {
    enable = true;
    enableMcpIntegration = true;
    package = codex-package;
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

    # codex-notify wiring. Turn completion is driven by the Stop hook (the
    # legacy `notify` config key is slated for removal); codex-notify always
    # exits 0 so it never blocks a turn. UserPromptSubmit stamps the per-turn
    # start, and /goal continuations bypass it - which is what lets
    # codex-notify recognize goal checkpoints. No SessionEnd hook: it fires on
    # every teardown with a constant reason, so stale state is instead GC'd by
    # codex-notify's seven-day TTL.
    hooks = {
      UserPromptSubmit = [
        {
          matcher = ".*";
          hooks = [
            {
              type = "command";
              command = "${lib.getExe codex-notify} prompt";
              timeout = 3;
            }
          ];
        }
      ];

      Stop = [
        {
          matcher = ".*";
          hooks = [
            {
              type = "command";
              command = "${lib.getExe codex-notify} notify Codex ${codex-notify-min-duration}";
              timeout = 3;
            }
          ];
        }
      ];
    };
  };
}
