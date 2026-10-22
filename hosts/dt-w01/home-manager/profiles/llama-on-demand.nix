{
  config,
  inputs,
  lib,
  pkgs,
  ...
}: let
  cfg = config.services.llama-on-demand;
  llama-package = inputs.llama-on-demand.lib.mkPackage {
    inherit pkgs;
    cudaSupport = true;
  };
  # Windows Tailscale owns the persistent route; this script only registers or
  # removes our mount. Keep a private copy of the published endpoint so cleanup
  # also works if the application has already removed its discovery file.
  windows-publish = ''
    param([string]$Action, [string]$Target)
    $ErrorActionPreference = 'Stop'
    $ProgressPreference = 'SilentlyContinue'
    $tailscale = (Get-Command tailscale.exe -ErrorAction Stop).Source
    $raw = & $tailscale serve status --json
    if ($LASTEXITCODE -ne 0) { throw 'Cannot read Tailscale Serve configuration' }
    $handler = $null
    foreach ($web in ($raw | ConvertFrom-Json).Web.PSObject.Properties) {
      if ($web.Name.EndsWith(':80')) { $handler = $web.Value.Handlers.'/llm/' }
    }
    if ($Action -eq 'ensure') {
      if ($handler.Proxy -eq $Target) { exit 0 }
      & $tailscale serve --bg --http=80 --set-path=/llm/ $Target
    } else {
      if ($handler.Proxy -ne $Target) { exit 0 }
      & $tailscale serve --http=80 --set-path=/llm/ off
    }
    if ($LASTEXITCODE -ne 0) { throw "Tailscale Serve $Action failed" }
  '';
  publish = pkgs.writeShellApplication {
    name = "publish-local-llm";
    runtimeInputs = [pkgs.coreutils pkgs.libiconv];
    text = ''
      action=$1
      published="$RUNTIME_DIRECTORY/published-endpoint"
      if [[ "$action" == ensure ]]; then
        target=$(tr -d '\r\n' < "$2")
      else
        [[ -r "$published" ]] || exit 0
        target=$(tr -d '\r\n' < "$published")
      fi
      [[ "$target" =~ ^http://127\.0\.0\.1:[0-9]+$ ]] || exit 1
      command=$(
        # PowerShell variables must reach Windows without shell expansion.
        # shellcheck disable=SC2016
        printf '& {\n%s\n} -Action "%s" -Target "%s"\n' \
          ${lib.escapeShellArg windows-publish} "$action" "$target" \
          | iconv -f UTF-8 -t UTF-16LE | base64 -w0
      )
      /mnt/c/WINDOWS/System32/WindowsPowerShell/v1.0/powershell.exe \
        -NonInteractive -OutputFormat Text -EncodedCommand "$command" </dev/null
      if [[ "$action" == ensure ]]; then
        printf '%s\n' "$target" > "$published"
      fi
    '';
  };
in {
  services.llama-on-demand = {
    enable = true;
    package = llama-package;
    # Windows Serve requires a TCP target; the application binds port 0 and
    # publishes its actual URL before notifying systemd that it is ready.
    host = "127.0.0.1";
    port = 0;
    settings = {
      # Tailscale Serve controls remote access; local callers need no API key.
      auth_required = false;
      idle_seconds = 30;
      fit_target_mib = 1024;
      queue_timeout = 3600;
      request_timeout = 3600;
      max_queue = 128;
    };
    models.sakura = {
      path = "${config.xdg.dataHome}/llama-on-demand/models/Sakura-Galtransl-7B-v3.7-IQ4_XS.gguf";
      repo = "SakuraLLM/Sakura-GalTransl-7B-v3.7";
      file = "Sakura-Galtransl-7B-v3.7-IQ4_XS.gguf";
      options = {
        ctx-size = 4096;
        threads = 8;
        threads-batch = 8;
        flash-attn = "on";
        cache-type-k = "q8_0";
        cache-type-v = "q8_0";
      };
    };
  };
  systemd.user.services.llama-on-demand.Service = {
    ExecStartPost = lib.mkAfter [
      "${lib.getExe publish} ensure ${lib.escapeShellArg cfg.endpoint-file}"
    ];
    # The application removes its endpoint on exit; use our published copy.
    # Windows being unavailable should not turn a normal shutdown into a failure.
    ExecStopPost = lib.mkAfter ["-${lib.getExe publish} remove"];
  };
}
