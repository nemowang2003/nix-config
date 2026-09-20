{
  self,
  config,
  pkgs,
  lib,
  cfg,
  ...
}: let
  models-lib = self.lib.models;
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
    self.packages.${pkgs.stdenv.hostPlatform.system}.codex-archive-backtrack
    self.packages.${pkgs.stdenv.hostPlatform.system}.codex-notify
  ];

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

    # Everything that selects the TCA gateway lives in this interactive
    # profile. Its provider registry and catalog are restricted to TCA.
    # `model` and `model_reasoning_effort` remain mutable TUI choices.
    profiles.tca = {
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
    profile-removed-paths.tca = [
      ["forced_login_method"]
      ["model_providers" "tca" "env_key"]
    ];

    # codex-notify wiring. Turn completion is driven by the Stop hook (the
    # legacy `notify` config key is slated for removal); codex-notify always
    # exits 0 so it never blocks a turn. No SessionEnd hook: it fires on every
    # teardown with a constant reason; stale route state can be removed with
    # `codex-notify cleanup`, using Codex's thread database as source of truth.
    hooks = {
      SessionStart = [
        {
          matcher = "^fork$";
          hooks = [
            {
              type = "command";
              command = "${lib.getExe self.packages.${pkgs.stdenv.hostPlatform.system}.codex-archive-backtrack} --codex ${lib.getExe pkgs.llm-agents.codex}";
              # The helper gives its nested Codex process 15 seconds; leave
              # enough outer-hook headroom for shutdown and state cleanup.
              timeout = 20;
              async = true;
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
              command = "${lib.getExe self.packages.${pkgs.stdenv.hostPlatform.system}.codex-notify} notify Codex";
              timeout = 3;
            }
          ];
        }
      ];
    };
  };
}
