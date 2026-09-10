{
  self,
  config,
  pkgs,
  lib,
  cfg,
  ...
}: let
  codex-notify = self.packages.${pkgs.stdenv.hostPlatform.system}.codex-notify;
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
  # One entry's worth of instruction boilerplate (base_instructions +
  # model_messages, ~37 kB), shared by every gateway model so the checked-in
  # catalog stays small. Refresh it from `codex debug models --bundled` when a
  # new Codex release changes the prompt scaffolding.
  catalog-template = builtins.fromJSON (builtins.readFile ./catalog-template.json);

  reasoning-levels = [
    {
      effort = "low";
      description = "Fast responses with lighter reasoning";
    }
    {
      effort = "high";
      description = "Extra high reasoning depth for complex problems";
    }
    {
      effort = "max";
      description = "Maximum reasoning depth for the hardest problems";
    }
  ];

  # Models served by the TCA LiteLLM gateway, listed under their OpenAI-protocol
  # names (the bare names are the Anthropic-protocol routes). List them with
  # `curl -H "Authorization: Bearer $TCA_KEY" $GW/v1/models` and read per-model
  # metadata from `$GW/model/info`. Context windows that the gateway does not
  # report are filled from the vendors' published specs.
  gateway-models = [
    {
      slug = "deepseek-v4-pro-openai";
      name = "DeepSeek-V4-Pro";
      description = "Frontier reasoning model served by the TCA gateway.";
      context = 1048576;
      effort = "max";
      priority = 1;
      vision = false;
    }
    {
      slug = "glm-5.3-openai";
      name = "GLM-5.3";
      description = "Zhipu flagship with a 1M-token context window.";
      context = 1048576;
      effort = "max";
      priority = 2;
      vision = false;
    }
    {
      slug = "kimi-k3-openai";
      name = "Kimi-K3";
      description = "Moonshot K3: 1M context with native vision.";
      context = 1048576;
      effort = "max";
      priority = 3;
      vision = true;
    }
    {
      slug = "qwen3.8-max-openai";
      name = "Qwen3.8-Max";
      description = "Alibaba flagship, multimodal.";
      context = 1000000;
      effort = "max";
      priority = 4;
      vision = true;
    }
    {
      slug = "qwen3.7-max-openai";
      name = "Qwen3.7-Max";
      description = "Alibaba Max tier, text only.";
      context = 1000000;
      effort = "high";
      priority = 5;
      vision = false;
    }
    {
      slug = "doubao-seed-2-0-pro-openai";
      name = "Doubao-Seed-2.0-Pro";
      description = "ByteDance Seed 2.0 Pro, multimodal.";
      context = 256000;
      effort = "high";
      priority = 6;
      vision = true;
    }
    {
      slug = "glm-5.2-openai";
      name = "GLM-5.2";
      description = "Zhipu GLM-5.2, 1M-token context window.";
      context = 1048576;
      effort = "high";
      priority = 7;
      vision = false;
    }
    {
      slug = "kimi-k2.7-code-openai";
      name = "Kimi-K2.7-Code";
      description = "Moonshot coding-specialised model.";
      context = 262144;
      effort = "high";
      priority = 8;
      vision = false;
    }
    {
      slug = "qwen3.7-plus-openai";
      name = "Qwen3.7-Plus";
      description = "Alibaba Plus tier.";
      context = 1000000;
      effort = "high";
      priority = 9;
      vision = false;
    }
    {
      slug = "qwen3.6-plus-openai";
      name = "Qwen3.6-Plus";
      description = "Alibaba Plus tier, previous generation.";
      context = 1000000;
      effort = "high";
      priority = 10;
      vision = false;
    }
    {
      slug = "deepseek-v4-flash-openai";
      name = "DeepSeek-V4-Flash";
      description = "Faster DeepSeek V4 tier.";
      context = 1048576;
      effort = "high";
      priority = 11;
      vision = false;
    }
    {
      slug = "deepseek-v4.1-flash-openai";
      name = "DeepSeek-V4.1-Flash";
      description = "Trial route whose upstream label expires on 2026-09-10.";
      context = 1048576;
      effort = "high";
      priority = 12;
      vision = false;
    }
    {
      slug = "kimi-k3-extra-openai";
      name = "Kimi-K3 (extra)";
      description = "Kimi K3 through the Moonshot direct channel.";
      context = 1048576;
      effort = "high";
      priority = 13;
      vision = true;
    }
    {
      slug = "deepseek-v4-flash-local-openai";
      name = "DeepSeek-V4-Flash (local)";
      description = "Self-hosted DeepSeek V4 Flash served through the gateway.";
      context = 1048576;
      effort = "high";
      priority = 14;
      vision = false;
    }
    {
      slug = "glm-4.6v-openai";
      name = "GLM-4.6V";
      description = "Zhipu vision model, self-hosted.";
      context = 131072;
      effort = "low";
      priority = 15;
      vision = true;
    }
  ];

  codex-catalog = pkgs.writeText "codex-tca-models.json" (builtins.toJSON {
    models =
      map
      (model:
        catalog-template
        // {
          slug = model.slug;
          display_name = model.name;
          description = model.description;
          context_window = model.context;
          max_context_window = model.context;
          default_reasoning_level = model.effort;
          supported_reasoning_levels = reasoning-levels;
          priority = model.priority;
          input_modalities = ["text"] ++ lib.optional model.vision "image";
        })
      gateway-models;
  });

  # Everything that selects the TCA gateway. All providers are expressed as the
  # built-in `openai` provider plus `openai_base_url`, so no `model_providers`
  # block is needed; other gateways would be siblings of this attrset.
  tca-settings = {
    model = "deepseek-v4-pro-openai";
    # Selector for the named provider defined in `model_providers.tca` below.
    # Named providers default to `supports_websockets = false` and
    # `requires_openai_auth = false`, so requests go straight to HTTPS and the
    # key comes from the TCA_API_KEY environment variable.
    model_provider = "tca";
    model_reasoning_effort = "max";
    model_catalog_json = codex-catalog;
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
    settings =
      tca-settings
      // {
        model_providers.tca = {
          name = "tca";
          base_url = "http://10.198.20.38:3821";
          wire_api = "responses";
          env_key = "TCA_API_KEY";
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

    # Provider profiles. `codex` without a profile already points at the TCA
    # gateway (settings above); `codex -p tca` selects the same thing
    # explicitly, and a second gateway becomes a sibling attrset plus one line
    # here. Profiles are written to $CODEX_HOME/<name>.config.toml.
    profiles.tca = tca-settings;

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
