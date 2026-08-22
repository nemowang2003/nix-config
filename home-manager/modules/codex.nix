{
  self,
  config,
  lib,
  options,
  pkgs,
  ...
}: let
  cfg = config.my.codex;
  upstream = options.programs.codex;

  # A thin wrapper around Home Manager's programs.codex module.
  # Keep upstream responsible for MCP, plugins, profiles, skills, hooks, and
  # generated settings; only replace the main config symlink with a mutable
  # activation merge.

  # A null package has no detectable version, so match programs.codex and
  # assume latest behavior.
  at-least = version: cfg.package == null || lib.versionAtLeast (lib.getVersion cfg.package) version;
  is-toml-config = at-least "0.2.0";
  mirrored-codex-options = self.lib.options.mirror-options {
    inherit upstream;
    excluded = ["enable" "custom-instructions"];
  };
in {
  imports = [
    (lib.mkRenamedOptionModule
      ["my" "codex" "custom-instructions"]
      ["my" "codex" "context"])
  ];

  options.my.codex =
    {
      enable = lib.mkEnableOption "mutable Codex configuration";
    }
    // mirrored-codex-options;

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
    lib.mkIf cfg.enable {
      programs.codex =
        {
          enable = true;
        }
        // removeAttrs cfg ["enable" "custom-instructions"];

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
