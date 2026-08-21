{
  pkgs,
  lib,
  ...
}: let
  notify-server-chan = pkgs.writeShellApplication {
    name = "agents-notify";
    runtimeInputs = [pkgs.curl pkgs.jq];
    text = ''
      title=''${1:-Codex}
      payload=''${2:-}
      url=''${AGENTS_NOTIFY_URL:-}

      if [ -z "$url" ] || [ -z "$payload" ]; then
        exit 0
      fi

      content=$(printf '%s' "$payload" | jq -r '(.last_assistant_message // .["last-assistant-message"] // "Task complete")')
      [ -n "$content" ] || content="Task complete"

      encoded_title=$(printf '%s' "$title" | jq -sRr '@uri')
      encoded=$(printf '%s' "$content" | jq -sRr '@uri')

      url=''${url//\{title\}/$encoded_title}
      url=''${url//\{content\}/$encoded}

      # Best-effort only. Never log the URL because it may contain a token.
      curl --fail --silent --show-error --max-time 10 --output /dev/null "$url" 2>/dev/null || true
    '';
  };
in {
  options.my.agent-notify = {
    package = lib.mkOption {
      type = lib.types.package;
      internal = true;
      description = "Shared server-chan notification script for coding agents.";
    };
  };

  config = {
    my.agent-notify.package = notify-server-chan;
    my.env-secrets.AGENTS_NOTIFY_URL.group = "common";
  };
}
