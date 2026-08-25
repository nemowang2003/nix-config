{
  lib,
  pkgs,
  cfg,
  ...
}: let
  uv = lib.getExe pkgs.uv;
  codex = lib.getExe pkgs.llm-agents.codex;
  user-home = "/home/${cfg.user}";
  # Materialized wholesale by home-manager's secrets module from
  # secrets/common/env; KEY=VALUE data is natively parsable by systemd.
  codex-env-file = "${user-home}/.config/sops-nix/env/common";
in {
  systemd = {
    services.codex-app-server = {
      description = "Codex app-server daemon shared by the TUI and the reply relay";
      wantedBy = ["multi-user.target"];

      serviceConfig = {
        Type = "simple";
        User = cfg.user;
        WorkingDirectory = user-home;
        EnvironmentFile = codex-env-file;
        Environment = [
          "XDG_CACHE_HOME=${user-home}/.cache"
          "XDG_CONFIG_HOME=${user-home}/.config"
          "XDG_STATE_HOME=${user-home}/.local/state"
        ];
        ExecStartPre = "${lib.getExe' pkgs.coreutils "rm"} -f ${user-home}/.codex/app-server-control/app-server-control.sock";
        ExecStart = "${codex} app-server --listen unix://";
        Restart = "on-failure";
        RestartSec = "2s";
        KillSignal = "SIGINT";
        TimeoutStopSec = "30s";
        LimitNOFILE = "65536";
      };
    };

    services.skyland-auto-sign = {
      description = "Skyland Auto Sign Service";
      after = ["network-online.target"];
      wants = ["network-online.target"];

      serviceConfig = {
        Type = "oneshot";
        User = cfg.user;
        WorkingDirectory = "/home/${cfg.user}/skyland-auto-sign";
        ExecStart = "${uv} run src/main.py";
      };
    };

    timers.skyland-auto-sign = {
      description = "Run Skyland Auto Sign daily";
      wantedBy = ["timers.target"];
      timerConfig = {
        OnCalendar = "*-*-* 00:00:00";
        Persistent = true;
        Unit = "skyland-auto-sign.service";
      };
    };
  };

  system.stateVersion = "25.05";
}
