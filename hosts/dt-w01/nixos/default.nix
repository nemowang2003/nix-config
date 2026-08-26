{
  lib,
  pkgs,
  cfg,
  ...
}: let
  codex = lib.getExe pkgs.llm-agents.codex;
  codex-reply = lib.getExe pkgs.nemowang2003.codex-reply;
  user-home = "/home/${cfg.user}";
  # Materialized wholesale by home-manager's secrets module from
  # secrets/common/env; KEY=VALUE data is natively parsable by systemd.
  codex-env-file = "${user-home}/.config/sops-nix/env/common";
  wecom-config = "${user-home}/.config/codex-reply/wecom.json";
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

    services.codex-reply = {
      description = "企业微信智能机器人长连接：投递 codex-notify 路由好的通知，并把用户回复注入本地 app-server";
      after = ["codex-app-server.service"];
      wants = ["codex-app-server.service"];
      wantedBy = ["multi-user.target"];

      serviceConfig = {
        Type = "simple";
        User = cfg.user;
        WorkingDirectory = user-home;
        Environment = [
          "XDG_CACHE_HOME=${user-home}/.cache"
          "XDG_CONFIG_HOME=${user-home}/.config"
          "XDG_STATE_HOME=${user-home}/.local/state"
        ];
        ExecStart = "${codex-reply} --config ${wecom-config}";
        Restart = "on-failure";
        RestartSec = "5s";
        KillSignal = "SIGINT";
        TimeoutStopSec = "10s";
      };
    };

    # Keep the user systemd instance (and its timers) alive across WSL
    # sessions, e.g. the skyland-auto-sign daily user timer.
    tmpfiles.rules = [
      "f /var/lib/systemd/linger/${cfg.user} 0644 root root -"
    ];
  };

  system.stateVersion = "25.05";
}
