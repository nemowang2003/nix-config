{pkgs, ...}: let
  # Kept free of single quotes so it can be embedded in a single-quoted shell
  # string. Title and body travel as Base64 arguments, so no user content is
  # interpolated into the PowerShell source; using plain -Command instead of
  # -EncodedCommand also avoids tripping EDR heuristics.
  ps-toast-script = ''
    $t = [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($args[0]));
    $b = [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($args[1]));
    [Windows.UI.Notifications.ToastNotificationManager, Windows.UI.Notifications, ContentType = WindowsRuntime] | Out-Null;
    [Windows.Data.Xml.Dom.XmlDocument, Windows.Data.Xml.Dom.XmlDocument, ContentType = WindowsRuntime] | Out-Null;
    $xmlText = "<toast><visual><binding template=""ToastGeneric""><text>{0}</text><text>{1}</text></binding></visual></toast>" -f [System.Security.SecurityElement]::Escape($t), [System.Security.SecurityElement]::Escape($b);
    $doc = New-Object Windows.Data.Xml.Dom.XmlDocument;
    $doc.LoadXml($xmlText);
    $toast = New-Object Windows.UI.Notifications.ToastNotification($doc);
    [Windows.UI.Notifications.ToastNotificationManager]::CreateToastNotifier("Codex").Show($toast);
  '';
in
  pkgs.writeShellApplication {
    name = "notify";
    runtimeInputs = [
      pkgs.coreutils
      pkgs.curl
      pkgs.gnugrep
      pkgs.jq
    ];
    text = ''
      mode=''${1:-}
      title=''${2:-Codex}
      content=''${3:-}

      is_wsl() {
        case "$(uname -r)" in
          *icrosoft*|*WSL*) return 0 ;;
          *) return 1 ;;
        esac
      }

      is_ssh() {
        local client_pid

        # The pane's environment is frozen when its shell first starts, so a
        # session created over SSH and reattached from a local terminal would
        # still look like SSH. Inspect the currently attached tmux client's
        # environment instead; Codex allows one active TUI per session, so
        # there is a single client to ask.
        if [ -n "''${TMUX:-}" ] && command -v tmux >/dev/null 2>&1; then
          client_pid=$(tmux display-message -p '#{client_pid}' 2>/dev/null || true)
          if [ -n "$client_pid" ] && [ -r "/proc/$client_pid/environ" ]; then
            if tr '\0' '\n' < "/proc/$client_pid/environ" 2>/dev/null | grep -qE '^SSH_(CONNECTION|CLIENT|TTY)='; then
              return 0
            fi
            return 1
          fi
        fi

        [ -n "''${SSH_CONNECTION:-}''${SSH_CLIENT:-}''${SSH_TTY:-}" ]
      }

      osc_tty() {
        # Inside tmux the pane's own tty belongs to the tmux server, so write
        # straight to the attached client's real terminal instead. Codex only
        # allows one active TUI per session, so there is a single client tty.
        if [ -n "''${TMUX:-}" ] && command -v tmux >/dev/null 2>&1; then
          tmux display-message -p '#{client_tty}' 2>/dev/null || true
        elif is_ssh; then
          printf '%s' "''${SSH_TTY:-}"
        elif [ -c /dev/tty ]; then
          printf '%s' /dev/tty
        fi
      }

      # OSC 9 is the widest-supported notification escape sequence (iTerm2,
      # WezTerm, kitty, Ghostty). Codex runs notify with null stdio, so write
      # straight to the session tty instead of stdout: over SSH that is the
      # remote terminal emulator, which raises the notification itself.
      notify_osc() {
        local tty_device msg

        tty_device=$(osc_tty)
        [ -n "$tty_device" ] || return 0
        [ -w "$tty_device" ] || return 0

        msg=$(printf '%s: %s' "$1" "$2" | tr -d '\000-\037\177')
        [ -n "$msg" ] || return 0
        printf '\033]9;%s\007' "$msg" > "$tty_device" 2>/dev/null || true
      }

      notify_wsl() {
        local ps_bin b64_title b64_body ps_script

        ps_bin=$(command -v powershell.exe 2>/dev/null || true)
        if [ -z "$ps_bin" ]; then
          ps_bin=/mnt/c/Windows/System32/WindowsPowerShell/v1.0/powershell.exe
        fi
        [ -f "$ps_bin" ] || return 0

        b64_title=$(printf '%s' "$1" | base64)
        b64_body=$(printf '%s' "$2" | base64)
        # shellcheck disable=SC2016
        ps_script='${ps-toast-script}'

        "$ps_bin" -NoProfile -NonInteractive -WindowStyle Hidden -Command "$ps_script" "$b64_title" "$b64_body" </dev/null >/dev/null 2>&1 || true
      }

      notify_local() {
        if is_ssh; then
          # Over SSH the only visible surface is the remote terminal.
          notify_osc "$1" "$2"
        elif is_wsl; then
          # Windows Terminal and friends do not implement OSC notification
          # toasts; show it on the Windows desktop instead.
          notify_wsl "$1" "$2"
        else
          notify_osc "$1" "$2"
        fi
      }

      notify_remote() {
        local url encoded_title encoded

        # WEBHOOK_NOTIFY_URL is a template URL. The literal {title} and
        # {content} placeholders are replaced with the percent-encoded title
        # and body before the request is sent.
        url=''${WEBHOOK_NOTIFY_URL:-}
        [ -n "$url" ] || return 0

        encoded_title=$(printf '%s' "$1" | jq -sRr '@uri')
        encoded=$(printf '%s' "$2" | jq -sRr '@uri')

        url=''${url//\{title\}/$encoded_title}
        url=''${url//\{content\}/$encoded}

        # Best-effort only. Never log the URL because it may contain a token.
        curl --fail --silent --show-error --max-time 10 --output /dev/null "$url" 2>/dev/null || true
      }

      case "$mode" in
        local)
          notify_local "$title" "$content"
          ;;
        remote)
          notify_remote "$title" "$content"
          ;;
        all)
          notify_local "$title" "$content"
          notify_remote "$title" "$content"
          ;;
      esac
    '';
  }
