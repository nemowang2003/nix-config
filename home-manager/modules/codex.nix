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
  mirror-option = name:
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
  at-least = version: cfg.package == null || lib.versionAtLeast (lib.getVersion cfg.package) version;
  is-toml-config = at-least "0.2.0";
in {
  imports = [
    (lib.mkRenamedOptionModule
      ["my" "codex" "custom-instructions"]
      ["my" "codex" "context"])
  ];

  options.my.codex = {
    enable = lib.mkEnableOption "mutable Codex configuration";

    package = mirror-option "package";
    enableMcpIntegration = mirror-option "enableMcpIntegration";
    settings = mirror-option "settings";
    profiles = mirror-option "profiles";
    context = mirror-option "context";
    contextOverride = mirror-option "contextOverride";
    hooks = mirror-option "hooks";
    plugins = mirror-option "plugins";
    marketplaces = mirror-option "marketplaces";
    skills = mirror-option "skills";
    rules = mirror-option "rules";
  };

  config = let
    use-xdg-directories = config.home.preferXdgDirectories && is-toml-config;
    xdg-config-home = lib.removePrefix config.home.homeDirectory config.xdg.configHome;
    config-dir =
      if use-xdg-directories
      then "${xdg-config-home}/codex"
      else ".codex";
    config-file-name =
      if is-toml-config
      then "config.toml"
      else "config.yaml";
    config-target = "${config-dir}/${config-file-name}";
    config-path = "${config.home.homeDirectory}/${config-target}";
    has-config-source = lib.hasAttrByPath [config-target "source"] config.home.file;
    config-source = lib.getAttrFromPath [config-target "source"] config.home.file;

    yj = lib.getExe pkgs.yj;
    jq = lib.getExe pkgs.jq;
    json-from-config =
      if is-toml-config
      then "${yj} -tj"
      else "${yj} -yj";
    config-from-json =
      if is-toml-config
      then "${yj} -jt"
      else "${yj} -jy";
  in
    mkIf cfg.enable {
      programs.codex = {
        enable = true;
        package = cfg.package;
        enableMcpIntegration = cfg.enableMcpIntegration;
        settings = cfg.settings;
        profiles = cfg.profiles;
        context = cfg.context;
        contextOverride = cfg.contextOverride;
        hooks = cfg.hooks;
        plugins = cfg.plugins;
        marketplaces = cfg.marketplaces;
        skills = cfg.skills;
        rules = cfg.rules;
      };

      # Keep Codex config mutable because Codex writes trust/bookkeeping state to
      # config.toml at runtime. See:
      # https://github.com/nix-community/home-manager/issues/9397
      home = {
        file.${config-target}.enable = lib.mkForce false;

        activation.mutable-codex-config = lib.mkIf has-config-source (
          lib.hm.dag.entryAfter ["writeBoundary"] ''
            (
              CONFIG_PATH=${lib.escapeShellArg config-path}
              CONFIG_BACKUP="$CONFIG_PATH.$HOME_MANAGER_BACKUP_EXT"

              OLD_JSON=$(mktemp)
              NEW_JSON=$(mktemp)
              MERGED_JSON=$(mktemp)
              MERGED_CONFIG=$(mktemp)
              trap 'rm -f "$OLD_JSON" "$NEW_JSON" "$MERGED_JSON" "$MERGED_CONFIG"' EXIT

              $DRY_RUN_CMD mkdir -p "$(dirname "$CONFIG_PATH")"

              if [ -f "$CONFIG_PATH" ]; then
                ${json-from-config} < "$CONFIG_PATH" > "$OLD_JSON"
              else
                echo "{}" > "$OLD_JSON"
              fi

              ${json-from-config} < "${config-source}" > "$NEW_JSON"
              ${jq} -s '.[0] * .[1]' "$OLD_JSON" "$NEW_JSON" > "$MERGED_JSON"
              ${config-from-json} < "$MERGED_JSON" > "$MERGED_CONFIG"

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
