{
  pkgs,
  min-duration ? 300,
  ...
}: let
  lib = pkgs.lib;
  serverchan-notify = pkgs.callPackage ./serverchan-notify.nix {};

  # Windows only raises a banner for toasts whose AUMID belongs to a
  # registered app; arbitrary unregistered AUMIDs are silently filed into the
  # notification center. Windows Terminal's packaged AUMID works out of the
  # box, and clicking the toast focuses the terminal.
  win-aumid = "Microsoft.WindowsTerminal_8wekyb3d8bbwe!App";

  # Kept free of single quotes so it can be embedded in a single-quoted shell
  # string. Title and body travel as Base64, whose characters are inert inside
  # double-quoted PowerShell literals, so LLM-generated content can never
  # splice into the command line.
  ps-toast-script = ''
    $t = [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String("%s"));
    $b = [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String("%s"));
    [Windows.UI.Notifications.ToastNotificationManager, Windows.UI.Notifications, ContentType = WindowsRuntime] | Out-Null;
    [Windows.Data.Xml.Dom.XmlDocument, Windows.Data.Xml.Dom.XmlDocument, ContentType = WindowsRuntime] | Out-Null;
    $xmlText = "<toast><visual><binding template=""ToastGeneric""><text>{0}</text><text>{1}</text></binding></visual></toast>" -f [System.Security.SecurityElement]::Escape($t), [System.Security.SecurityElement]::Escape($b);
    $doc = New-Object Windows.Data.Xml.Dom.XmlDocument;
    $doc.LoadXml($xmlText);
    $toast = New-Object Windows.UI.Notifications.ToastNotification($doc);
    [Windows.UI.Notifications.ToastNotificationManager]::CreateToastNotifier("${win-aumid}").Show($toast);
  '';
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
      # shellcheck disable=SC2016
      ps_script='${ps-toast-script}'

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

      is_wsl() {
        case "$(uname -r)" in
          *icrosoft*|*WSL*) return 0 ;;
          *) return 1 ;;
        esac
      }

      notify_wsl() {
        local ps_bin b64_title b64_body ps_cmd

        # PATH lookup is both the transport check and the "interactive Windows
        # session" check: WSL shells started from Windows Terminal have the
        # interop dirs on PATH, while SSH sessions do not, so sessions driven
        # from another machine skip the toast here.
        ps_bin=$(command -v powershell.exe 2>/dev/null || true)
        [ -n "$ps_bin" ] || return 0

        b64_title=$(printf '%s' "$1" | tr -d '\000-\037\177' | base64)
        b64_body=$(printf '%s' "$2" | tr -d '\000-\037\177' | base64)

        # shellcheck disable=SC2059 # ps_script is a static, intentionally templated string.
        ps_cmd=$(printf "$ps_script" "$b64_title" "$b64_body")
        "$ps_bin" -NonInteractive -WindowStyle Hidden -Command "$ps_cmd" </dev/null >/dev/null 2>&1 || true
      }

      notify_local() {
        if is_wsl; then
          # Other platforms keep Codex's built-in TUI notification path.
          notify_wsl "$1" "$2"
        fi
      }

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

      # The local notification is unconditional; only the remote ping is
      # throttled by duration below.
      notify_local "$title" "$content"
      log "notify local done"

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
