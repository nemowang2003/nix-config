{
  pkgs,
  min-duration ? 300,
  ...
}: let
  lib = pkgs.lib;
  serverchan-notify = pkgs.callPackage ./serverchan-notify.nix {};
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
      log_dir="''${XDG_CACHE_HOME:-$HOME/.cache}/codex-notify"
      serverchan_notify_bin=${lib.getExe serverchan-notify}

      log() {
        mkdir -p "$log_dir" || return 0
        printf '[%s] %s\n' "$(date '+%F %T %z')" "$*" >> "$log_dir/notify.log"
      }

      # Codex SessionStart hooks receive the session JSON on stdin.
      if [ "''${1:-}" = "start" ]; then
        session_id=$(jq -r '.session_id // empty' 2>/dev/null || true)
        if [ -n "$session_id" ]; then
          mkdir -p "$state_dir"
          key=$(printf '%s' "$session_id" | sha256sum | cut -d' ' -f1)
          date +%s > "$state_dir/start-$key"
          find "$state_dir" -maxdepth 1 -name 'start-*' -type f -mtime +7 -delete 2>/dev/null || true
          log "start session=$session_id marker=start-$key"
        else
          log "start: no session_id in hook payload"
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
      if [ -z "$payload" ]; then
        log "notify skip: no payload argument (argc=$#)"
        exit 0
      fi

      payload_type=$(printf '%s' "$payload" | jq -r '.type // empty' 2>/dev/null || true)
      if [ "$payload_type" != "agent-turn-complete" ]; then
        log "notify skip: unhandled payload type='$payload_type'"
        exit 0
      fi

      thread_id=$(printf '%s' "$payload" | jq -r '.["thread-id"] // empty' 2>/dev/null || true)
      content=$(printf '%s' "$payload" | jq -r '.last_assistant_message // .["last-assistant-message"] // "Task complete"' 2>/dev/null || true)
      [ -n "$content" ] || content="Task complete"

      log "notify type=$payload_type thread=$thread_id content_bytes=''${#content}"

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
          log "notify marker=found thread=$thread_id duration=$duration"
        else
          log "notify marker=missing thread=$thread_id"
        fi
      fi

      # Missing start marker means duration is unknown; skip the remote ping
      # rather than degrade into notifying every short turn.
      if [ "$duration" -ge "$threshold" ] 2>/dev/null; then
        log "notify serverchan duration=$duration threshold=$threshold"
        "$serverchan_notify_bin" "$title" "$content"
        rc=$?
        log "notify serverchan done rc=$rc"
      else
        log "notify serverchan skip duration=$duration threshold=$threshold"
      fi
    '';
  }
