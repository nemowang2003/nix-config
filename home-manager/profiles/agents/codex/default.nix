{
  self,
  config,
  pkgs,
  lib,
  cfg,
  ...
}: let
  codex-notify = self.packages.${pkgs.stdenv.hostPlatform.system}.codex-notify;
  # One entry's worth of instruction boilerplate (base_instructions +
  # model_messages, ~37 kB), shared by every gateway model so the checked-in
  # catalog stays small. Refresh it from `codex debug models --bundled` when a
  # new Codex release changes the prompt scaffolding.
  catalog-template = builtins.fromJSON (builtins.readFile ./catalog-template.json);

  models-lib = self.lib.models;

  codex-catalog = pkgs.writeText "codex-tca-models.json" (builtins.toJSON {
    models =
      map
      (model:
        catalog-template
        // {
          slug = models-lib.openai-slug model.id;
          display_name = model.name;
          description = model.description;
          context_window = model.context;
          max_context_window = model.context;
          default_reasoning_level = model.effort;
          supported_reasoning_levels = models-lib.reasoning-levels;
          priority = model.priority;
          input_modalities = ["text"] ++ lib.optional model.vision "image";
        })
      models-lib.models;
  });

  # Everything that selects the TCA gateway lives in this profile and therefore
  # only in $CODEX_HOME/tca.config.toml - never in the base config.toml, which
  # stays limited to client behaviour. Other gateways would be siblings of this
  # attrset plus a `profiles.<name>` entry below.
  #
  # `model` and `model_reasoning_effort` are deliberately absent: the TUI
  # writes the selected model back to the profile file, and the mutable merge
  # lets the declaration win key by key, so pinning them here would undo that
  # choice on every activation. The gateway's models all come from the catalog
  # below; pick one with the model picker or `/model`.
  tca-settings = {
    # Selector for the named provider defined in `model_providers.tca` below.
    model_provider = "tca";
    model_catalog_json = codex-catalog;
    model_providers.tca = {
      name = models-lib.providers.tca.name;
      base_url = models-lib.providers.tca.base-url;
      wire_api = "responses";
      requires_openai_auth = false;

      # A provider-owned auth manager avoids loading or refreshing the global
      # ChatGPT credentials in auth.json. Its token cache is process-local;
      # refresh_interval_ms = 0 reruns printenv only after a 401 response.
      auth = {
        command = lib.getExe' pkgs.coreutils "printenv";
        args = [models-lib.providers.tca.key-env];
        refresh_interval_ms = 0;
      };
    };
  };
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

  # 企业微信智能机器人凭据 for codex-wecom-relay; declared only once the
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
      path = "${config.xdg.configHome}/codex-wecom-relay/wecom.json";
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
    package = pkgs.llm-agents.codex;
    contexts = [./AGENTS.md];
    settings = {
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

    # Provider profiles: `codex -p tca` selects the gateway. The profile file
    # $CODEX_HOME/tca.config.toml is mutable (see home-manager/modules/codex.nix);
    # a second gateway becomes a sibling attrset plus one line here.
    profiles.tca = tca-settings;

    # codex-notify wiring. Turn completion is driven by the Stop hook (the
    # legacy `notify` config key is slated for removal); codex-notify always
    # exits 0 so it never blocks a turn. No SessionEnd hook: it fires on every
    # teardown with a constant reason; stale route state can be removed with
    # `codex-notify cleanup`, using Codex's thread database as source of truth.
    hooks = {
      Stop = [
        {
          matcher = ".*";
          hooks = [
            {
              type = "command";
              command = "${lib.getExe codex-notify} notify Codex";
              timeout = 3;
            }
          ];
        }
      ];
    };
  };
}
