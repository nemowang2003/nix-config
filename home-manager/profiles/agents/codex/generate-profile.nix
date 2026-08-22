{
  config,
  pkgs,
  lib,
  ...
}: let
  agent-languages =
    lib.filterAttrs
    (_: language: language.enable && language.agent.enable)
    config.my.languages;
  lsp-servers =
    lib.filterAttrs
    (name: server: server.enable && server.agent.enable)
    config.my.lsp.servers;
  language-mcp-servers =
    lib.mapAttrs
    (name: language:
      lib.genAttrs
      (map (server: "${server}-lsp") (lib.filter (server: lsp-servers ? ${server}) language.lsp))
      (_: {enabled = true;}))
    agent-languages;
  language-names = lib.attrNames language-mcp-servers;
  languages-json = builtins.toJSON language-mcp-servers;

  codex-generate-profile = pkgs.writeShellApplication {
    name = "codex-generate-profile";
    runtimeInputs = [pkgs.yj pkgs.jq];
    text = ''
      language=''${1:-}
      project_dir=''${2:-.}

      if [ -z "$language" ]; then
        echo "usage: codex-generate-profile <${lib.concatStringsSep "|" language-names}> [project-dir]" >&2
        exit 1
      fi

      servers=$(jq -cn --arg lang "$language" --argjson all '${languages-json}' '$all[$lang] // empty')
      if [ -z "$servers" ]; then
        echo "codex-generate-profile: unknown language '$language' (supported: ${lib.concatStringsSep ", " language-names})" >&2
        exit 1
      fi

      config_dir="$project_dir/.codex"
      config_file="$config_dir/config.toml"
      mkdir -p "$config_dir"

      old_json=$(mktemp)
      add_json=$(mktemp)
      merged_json=$(mktemp)
      merged_toml=$(mktemp)
      trap 'rm -f "$old_json" "$add_json" "$merged_json" "$merged_toml"' EXIT

      if [ -f "$config_file" ]; then
        yj -tj < "$config_file" > "$old_json"
      else
        printf '{}\n' > "$old_json"
      fi

      jq -n --argjson servers "$servers" '{mcp_servers: $servers}' > "$add_json"

      jq -s '
        .[0] as $base
        | .[1] as $add
        | $base
        | .mcp_servers //= {}
        | reduce ($add.mcp_servers | to_entries[]) as $entry (.; .mcp_servers[$entry.key] = ((.mcp_servers[$entry.key] // {}) + $entry.value))
      ' "$old_json" "$add_json" > "$merged_json"

      yj -jt < "$merged_json" > "$merged_toml"
      install -m 644 "$merged_toml" "$config_file"

      echo "codex-generate-profile: enabled $language LSP servers in $config_file"
    '';
  };
in {
  home.packages = lib.mkIf config.my.codex.enable [codex-generate-profile];

  programs.zsh.initContent = lib.mkIf config.my.codex.enable (lib.mkAfter ''
    function _codex-generate-profile() {
      _arguments \
        '1:language:(${lib.concatStringsSep " " language-names})' \
        '2:directory:_directories'
    }
    compdef _codex-generate-profile codex-generate-profile
  '');
}
