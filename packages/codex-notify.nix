{
  pkgs,
  min-duration ? 300,
  ...
}: let
  lib = pkgs.lib;
  notify = pkgs.callPackage ./notify.nix {};
in
  pkgs.writeShellApplication {
    name = "codex-notify";
    runtimeInputs = [
      pkgs.coreutils
      pkgs.findutils
      pkgs.jq
    ];
    text = ''
      state_dir="''${XDG_STATE_HOME:-$HOME/.local/state}/codex-notify"
      notify_bin=${lib.getExe notify}

      # Codex SessionStart hooks receive the session JSON on stdin.
      if [ "''${1:-}" = "start" ]; then
        session_id=$(jq -r '.session_id // empty' 2>/dev/null || true)
        if [ -n "$session_id" ]; then
          mkdir -p "$state_dir"
          key=$(printf '%s' "$session_id" | sha256sum | cut -d' ' -f1)
          date +%s > "$state_dir/start-$key"
          find "$state_dir" -maxdepth 1 -name 'start-*' -type f -mtime +7 -delete 2>/dev/null || true
        fi
        exit 0
      fi

      title=''${1:-Codex}
      host=$(hostname -s 2>/dev/null || true)
      if [ -n "$host" ]; then
        title="$title@$host"
      fi
      threshold=''${2:-${toString min-duration}}
      payload=''${3:-}
      [ -n "$payload" ] || exit 0

      payload_type=$(printf '%s' "$payload" | jq -r '.type // empty' 2>/dev/null || true)
      [ "$payload_type" = "agent-turn-complete" ] || exit 0

      thread_id=$(printf '%s' "$payload" | jq -r '.["thread-id"] // empty' 2>/dev/null || true)
      content=$(printf '%s' "$payload" | jq -r '.last_assistant_message // .["last-assistant-message"] // "Task complete"' 2>/dev/null || true)
      [ -n "$content" ] || content="Task complete"

      # Legacy notify payloads carry no timing, so task start is recorded by
      # the SessionStart hook and looked up here by thread id.
      duration=-1
      if [ -n "$thread_id" ]; then
        mkdir -p "$state_dir"
        key=$(printf '%s' "$thread_id" | sha256sum | cut -d' ' -f1)
        marker="$state_dir/start-$key"
        if [ -r "$marker" ]; then
          start=$(cat "$marker")
          now=$(date +%s)
          case "$start" in
            *[!0-9]*)
              : ;;
            [0-9]*)
              if [ "$now" -ge "$start" ]; then
                duration=$((now - start))
              fi
              ;;
          esac
          rm -f "$marker"
        fi
      fi

      "$notify_bin" local "$title" "$content"

      # Missing start marker means duration is unknown; skip the remote ping
      # rather than degrade into notifying every short turn.
      if [ "$duration" -ge "$threshold" ] 2>/dev/null; then
        "$notify_bin" remote "$title" "$content"
      fi
    '';
  }
