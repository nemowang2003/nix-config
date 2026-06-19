{
  config,
  pkgs,
  lib,
  ...
}: let
  mutableSettings = {
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
  };
  tomlFile = (pkgs.formats.toml {}).generate "codex-config.toml" mutableSettings;
in {
  programs.codex.enable = true;

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

        ${yj} -tj < "${tomlFile}" > "$NEW_JSON"
        ${jq} -s '.[0] * .[1]' "$OLD_JSON" "$NEW_JSON" > "$MERGED_JSON"
        ${yj} -jt < "$MERGED_JSON" > "$MERGED_TOML"

        if [ -f "$CONFIG_PATH" ]; then
          $DRY_RUN_CMD cp -p "$CONFIG_PATH" "$CONFIG_BACKUP"
        fi

        $DRY_RUN_CMD install -m 644 "$MERGED_TOML" "$CONFIG_PATH"
      )
    '';
}
