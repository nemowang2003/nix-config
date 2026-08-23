{pkgs, ...}:
pkgs.writeShellApplication {
  name = "serverchan-notify";
  runtimeInputs = [
    pkgs.coreutils
    pkgs.curl
  ];
  text = ''
    log_dir="''${XDG_CACHE_HOME:-$HOME/.cache}/codex-notify"

    log() {
      mkdir -p "$log_dir" || return 0
      printf '[%s] %s\n' "$(date '+%F %T %z')" "$*" >> "$log_dir/notify.log"
    }

    title=''${1:-Codex}
    content=''${2:-}

    log "serverchan title=$title content_bytes=''${#content}"

    # Bare ServerChan³ endpoint (https://<uid>.push.ft07.com/send/<sendkey>.send).
    # POST so long bodies are not subject to URL length limits. Never log the
    # URL because it contains the sendkey.
    url=''${SERVERCHAN_SEND_URL:-}
    if [ -z "$url" ]; then
      log "serverchan skip: SERVERCHAN_SEND_URL not set"
      exit 0
    fi

    if http_code=$(
      curl \
        --fail \
        --silent \
        --show-error \
        --max-time 10 \
        --request POST \
        --data-urlencode "title=$title" \
        --data-urlencode "desp=$content" \
        --output /dev/null \
        --write-out '%{http_code}' \
        "$url" 2>/dev/null
    ); then
      rc=0
    else
      rc=$?
    fi
    log "serverchan done http_code=$http_code rc=$rc"
  '';
}
