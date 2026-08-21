{
  config,
  lib,
  options,
  pkgs,
  ...
}: let
  inherit (lib) mkIf mkOption;

  cfg = config.my.codex;
  upstream = options.programs.codex;

  # A thin wrapper around Home Manager's programs.codex module.
  # Keep upstream responsible for MCP, plugins, profiles, skills, hooks, and
  # generated settings; only replace the main config symlink with a mutable
  # activation merge.
  mirrorOption = name:
    mkOption ({
        inherit (upstream.${name}) type default description;
      }
      // lib.optionalAttrs (upstream.${name} ? defaultText) {
        inherit (upstream.${name}) defaultText;
      }
      // lib.optionalAttrs (upstream.${name} ? example) {
        inherit (upstream.${name}) example;
      });

  # A null package has no detectable version, so match programs.codex and
  # assume latest behavior.
  atLeast = version: cfg.package == null || lib.versionAtLeast (lib.getVersion cfg.package) version;
  isTomlConfig = atLeast "0.2.0";
in {
  imports = [
    (lib.mkRenamedOptionModule
      ["my" "codex" "custom-instructions"]
      ["my" "codex" "context"])
  ];

  options.my.codex = {
    enable = lib.mkEnableOption "mutable Codex configuration";

    package = mirrorOption "package";
    enableMcpIntegration = mirrorOption "enableMcpIntegration";
    settings = mirrorOption "settings";
    profiles = mirrorOption "profiles";
    context = mirrorOption "context";
    contextOverride = mirrorOption "contextOverride";
    hooks = mirrorOption "hooks";
    plugins = mirrorOption "plugins";
    marketplaces = mirrorOption "marketplaces";
    skills = mirrorOption "skills";
    rules = mirrorOption "rules";
  };

  config = let
    useXdgDirectories = config.home.preferXdgDirectories && isTomlConfig;
    xdgConfigHome = lib.removePrefix config.home.homeDirectory config.xdg.configHome;
    configDir =
      if useXdgDirectories
      then "${xdgConfigHome}/codex"
      else ".codex";
    configFileName =
      if isTomlConfig
      then "config.toml"
      else "config.yaml";
    configTarget = "${configDir}/${configFileName}";
    configPath = "${config.home.homeDirectory}/${configTarget}";
    hasConfigSource = lib.hasAttrByPath [configTarget "source"] config.home.file;
    configSource = lib.getAttrFromPath [configTarget "source"] config.home.file;

    yj = lib.getExe pkgs.yj;
    jq = lib.getExe pkgs.jq;
    jsonFromConfig =
      if isTomlConfig
      then "${yj} -tj"
      else "${yj} -yj";
    configFromJson =
      if isTomlConfig
      then "${yj} -jt"
      else "${yj} -jy";
  in
    mkIf cfg.enable {
      programs.codex = {
        enable = true;
        inherit
          (cfg)
          package
          enableMcpIntegration
          settings
          profiles
          context
          contextOverride
          hooks
          plugins
          marketplaces
          skills
          rules
          ;
      };

      # Keep Codex config mutable because Codex writes trust/bookkeeping state to
      # config.toml at runtime. See:
      # https://github.com/nix-community/home-manager/issues/9397
      home = {
        file.${configTarget}.enable = lib.mkForce false;

        activation.mutableCodexConfig = lib.mkIf hasConfigSource (
          lib.hm.dag.entryAfter ["writeBoundary"] ''
            (
              CONFIG_PATH=${lib.escapeShellArg configPath}
              CONFIG_BACKUP="$CONFIG_PATH.$HOME_MANAGER_BACKUP_EXT"

              OLD_JSON=$(mktemp)
              NEW_JSON=$(mktemp)
              MERGED_JSON=$(mktemp)
              MERGED_CONFIG=$(mktemp)
              trap 'rm -f "$OLD_JSON" "$NEW_JSON" "$MERGED_JSON" "$MERGED_CONFIG"' EXIT

              $DRY_RUN_CMD mkdir -p "$(dirname "$CONFIG_PATH")"

              if [ -f "$CONFIG_PATH" ]; then
                ${jsonFromConfig} < "$CONFIG_PATH" > "$OLD_JSON"
              else
                echo "{}" > "$OLD_JSON"
              fi

              ${jsonFromConfig} < "${configSource}" > "$NEW_JSON"
              ${jq} -s '.[0] * .[1]' "$OLD_JSON" "$NEW_JSON" > "$MERGED_JSON"
              ${configFromJson} < "$MERGED_JSON" > "$MERGED_CONFIG"

              if [ -f "$CONFIG_PATH" ]; then
                $DRY_RUN_CMD cp -p "$CONFIG_PATH" "$CONFIG_BACKUP"
              fi

              $DRY_RUN_CMD install -m 644 "$MERGED_CONFIG" "$CONFIG_PATH"
            )
          ''
        );
      };
    };
}
