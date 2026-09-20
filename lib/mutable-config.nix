{lib}: let
  # `yj` round-trips both encodings through JSON, which is what lets the merge
  # below stay format-agnostic: it only ever compares JSON trees.
  codecs = {
    toml = {
      decode = "-tj";
      encode = "-jt";
    };
    yaml = {
      decode = "-yj";
      encode = "-jy";
    };
  };
in {
  # Build the body of a Home Manager activation entry that merges a
  # declarative config file into the live one, with the declarative side
  # winning key by key.
  #
  # Programs that rewrite their own config at runtime (Codex writes trust
  # state and bookkeeping into config.toml) would otherwise lose those edits on
  # the next activation, so the generated file is not installed as a symlink:
  # the merge preserves everything already on disk that the declaration does
  # not mention. The previous file is kept next to the new one under
  # `$HOME_MANAGER_BACKUP_EXT`, and a dry run only touches the backup.
  #
  # The returned string relies on the environment Home Manager activation
  # provides (`DRY_RUN_CMD` and `HOME_MANAGER_BACKUP_EXT`), so it belongs in an
  # `home.activation` entry, e.g.
  #
  #     home.activation.mutable-example =
  #       lib.hm.dag.entryAfter ["writeBoundary"] (
  #         self.lib.mutable-config.mk-mutable-merge {
  #           inherit pkgs format path source;
  #         }
  #       );
  #
  # `format` selects the on-disk encoding ("toml" or "yaml"), `path` is the
  # live file, and `source` is the store path holding the declaration.
  mk-mutable-merge = {
    pkgs,
    format,
    path,
    source,
    removed-paths ? [],
  }: let
    codec =
      codecs.${format}
      or (throw "mk-mutable-merge: unsupported format '${format}'");
    yj = lib.getExe pkgs.yj;
    jq = lib.getExe pkgs.jq;
  in ''
    (
      CONFIG_PATH=${lib.escapeShellArg path}
      CONFIG_BACKUP="$CONFIG_PATH.$HOME_MANAGER_BACKUP_EXT"

      OLD_JSON=$(mktemp)
      NEW_JSON=$(mktemp)
      MERGED_JSON=$(mktemp)
      MERGED_CONFIG=$(mktemp)
      trap 'rm -f "$OLD_JSON" "$NEW_JSON" "$MERGED_JSON" "$MERGED_CONFIG"' EXIT

      $DRY_RUN_CMD mkdir -p "$(dirname "$CONFIG_PATH")"

      if [ -f "$CONFIG_PATH" ]; then
        ${yj} ${codec.decode} < "$CONFIG_PATH" > "$OLD_JSON"
      else
        echo "{}" > "$OLD_JSON"
      fi

      ${yj} ${codec.decode} < "${source}" > "$NEW_JSON"
      ${jq} -s --argjson removed '${builtins.toJSON removed-paths}' \
        '.[0] * .[1] | delpaths($removed)' \
        "$OLD_JSON" "$NEW_JSON" > "$MERGED_JSON"
      ${yj} ${codec.encode} < "$MERGED_JSON" > "$MERGED_CONFIG"

      if [ -f "$CONFIG_PATH" ]; then
        $DRY_RUN_CMD cp -p "$CONFIG_PATH" "$CONFIG_BACKUP"
      fi

      $DRY_RUN_CMD install -m 644 "$MERGED_CONFIG" "$CONFIG_PATH"
    )
  '';
}
