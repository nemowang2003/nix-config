{
  self,
  config,
  pkgs,
  lib,
  cfg,
  ...
}: let
  models-lib = self.lib.models;
  mk-hooks = codex-home: {
    Stop = [
      {
        matcher = ".*";
        hooks = [
          {
            type = "command";
            command = lib.escapeShellArgs (
              [
                (lib.getExe self.packages.${pkgs.stdenv.hostPlatform.system}.codex-notify)
                "notify"
                "Codex"
                "--codex-home"
                codex-home
              ]
              ++ lib.optional cfg.notify-wecom "--wecom-relay"
            );
            timeout = 3;
          }
        ];
      }
    ];
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

  home.packages = [
    self.packages.${pkgs.stdenv.hostPlatform.system}.codex-notify
  ];

  home.shellAliases."codex-list-sessions" = ''
    (
      for codex_home in ${lib.escapeShellArgs ["${config.home.homeDirectory}/.codex" "${config.home.homeDirectory}/.codex-tca"]}; do
        if [ -f "$codex_home/state_5.sqlite" ]; then
          printf '%s\n' "$codex_home"
          ${lib.getExe pkgs.sqlite} -readonly -header -column "$codex_home/state_5.sqlite" \
            "SELECT id, cwd, title FROM threads ORDER BY updated_at DESC;"
        fi
      done
    ) | $EDITOR
  '';

  my.codex = {
    enable = true;
    enableMcpIntegration = true;
    package = pkgs.llm-agents.codex;
    contexts = [./AGENTS.md];
    # Home Manager registers every entry under this directory as a skill,
    # preserving each skill's references, assets, and agent metadata.
    skills = ./skills;
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
        (name: server:
          lib.nameValuePair "${name}-lsp" {
            command = lib.getExe pkgs.mcp-language-server;
            args =
              [
                "-workspace"
                "."
                "-lsp"
                (
                  if server.command != null
                  then server.command
                  else lib.getExe server.package
                )
              ]
              ++ lib.optionals (server.args != []) (["--"] ++ server.args);
            enabled = false;
            disabled_tools = [
              "edit_file"
              "rename_symbol"
            ];
            startup_timeout_sec = 20;
            tool_timeout_sec = 120;
          })
        (lib.filterAttrs
          (name: server:
            lib.elem name (
              lib.unique (
                lib.concatMap
                (language: language.lsp)
                (lib.attrValues (
                  lib.filterAttrs
                  (_: language: language.enable && language.agent.enable)
                  config.my.languages
                ))
              )
            )
            && server.enable
            && server.agent.enable)
          config.my.lsp.servers);
    };

    # The official and TCA homes share tools and instructions, but their
    # provider routes, model defaults, credentials, and sessions are independent.
    settings.model_provider = "openai";
    tca-settings = {
      model_provider = "tca";
      model_catalog_json = pkgs.writeText "codex-tca-models.json" (builtins.toJSON {
        models =
          map
          (model:
            # Shared instruction boilerplate for each gateway model. Refresh
            # it from `codex debug models --bundled` after Codex changes the
            # bundled model prompts.
              (builtins.fromJSON (builtins.readFile ./catalog-template.json))
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
    removed-paths = [
      ["model_catalog_json"]
      ["model_providers" "tca"]
      ["profile"]
      ["profiles" "tca"]
    ];
    tca-removed-paths = [
      ["forced_chatgpt_workspace_id"]
      ["chatgpt_base_url"]
      ["openai_base_url"]
      ["apps"]
      ["plugins"]
      ["marketplaces"]
      ["features" "plugins"]
      ["profile"]
      ["profiles"]
      ["forced_login_method"]
      ["model_providers" "tca" "env_key"]
    ];

    # codex-notify wiring. Turn completion is driven by the Stop hook (the
    # legacy `notify` config key is slated for removal); codex-notify always
    # exits 0 so it never blocks a turn. No SessionEnd hook: it fires on every
    # teardown with a constant reason; stale route state can be removed with
    # `codex-notify cleanup`, using Codex's thread database as source of truth.
    hooks = mk-hooks "${config.home.homeDirectory}/.codex";
    tca-hooks = mk-hooks "${config.home.homeDirectory}/.codex-tca";
  };
}
