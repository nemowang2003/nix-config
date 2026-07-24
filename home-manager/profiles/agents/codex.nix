{
  config,
  pkgs,
  lib,
  ...
}: let
  lspServers = lib.filterAttrs (_: server: server.enable && server.agent.enable) config.my.lsp.servers;
  lspCommand = server:
    if server.command != null
    then server.command
    else lib.getExe server.package;
  mkLspMcpServer = server: {
    command = lib.getExe pkgs.mcp-language-server;
    args =
      [
        "-workspace"
        "."
        "-lsp"
        (lspCommand server)
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

  # Keep this transform in sync with Home Manager's
  # programs.codex.enableMcpIntegration implementation, but write it through
  # mutableCodexConfig below instead of home.file.
  shared-mcp-servers = lib.optionalAttrs (config.programs.mcp.enable && config.programs.mcp.servers != {}) (
    lib.mapAttrs (
      name: server:
        lib.hm.mcp.transformMcpServer {
          inherit server;
          exclude = [
            "headers"
            "type"
          ];
          extraTransforms = [
            (s: s // lib.optionalAttrs (s.headers or {} != {}) {http_headers = s.headers;})
            lib.hm.mcp.addType
            (lib.hm.mcp.wrapEnvFilesCommand {inherit pkgs name;})
          ];
        }
    )
    config.programs.mcp.servers
  );
  codex-lsp-mcp-servers =
    lib.mapAttrs'
    (name: server: lib.nameValuePair "${name}-lsp" (mkLspMcpServer server))
    lspServers;
  mcp-servers = shared-mcp-servers // codex-lsp-mcp-servers;

  settings =
    {
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
    }
    // lib.optionalAttrs (mcp-servers != {}) {
      mcp_servers = mcp-servers;
    };
  toml-file = (pkgs.formats.toml {}).generate "codex-config.toml" settings;
in {
  programs.codex = {
    enable = true;
    enableMcpIntegration = false;
    package = pkgs.llm-agents.codex;
  };

  # Keep Codex config mutable because Codex writes trust/bookkeeping state to
  # config.toml at runtime. See:
  # https://github.com/nix-community/home-manager/issues/9397
  home.activation.mutableCodexConfig = let
    yj = lib.getExe pkgs.yj;
    jq = lib.getExe pkgs.jq;
  in
    lib.hm.dag.entryAfter ["writeBoundary"] ''
      (
        CONFIG_PATH="${config.home.homeDirectory}/.codex/config.toml"
        CONFIG_BACKUP="$CONFIG_PATH.$HOME_MANAGER_BACKUP_EXT"

        OLD_JSON=$(mktemp)
        NEW_JSON=$(mktemp)
        MERGED_JSON=$(mktemp)
        MERGED_TOML=$(mktemp)
        trap 'rm -f "$OLD_JSON" "$NEW_JSON" "$MERGED_JSON" "$MERGED_TOML"' EXIT

        $DRY_RUN_CMD mkdir -p "$(dirname "$CONFIG_PATH")"

        if [ -f "$CONFIG_PATH" ]; then
          ${yj} -tj < "$CONFIG_PATH" > "$OLD_JSON"
        else
          echo "{}" > "$OLD_JSON"
        fi

        ${yj} -tj < "${toml-file}" > "$NEW_JSON"
        ${jq} -s '.[0] * .[1]' "$OLD_JSON" "$NEW_JSON" > "$MERGED_JSON"
        ${yj} -jt < "$MERGED_JSON" > "$MERGED_TOML"

        if [ -f "$CONFIG_PATH" ]; then
          $DRY_RUN_CMD cp -p "$CONFIG_PATH" "$CONFIG_BACKUP"
        fi

        $DRY_RUN_CMD install -m 644 "$MERGED_TOML" "$CONFIG_PATH"
      )
    '';
}
