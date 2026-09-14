{
  lib,
  pkgs,
  cfg,
  self,
  ...
}: let
  codex-reply = lib.getExe self.packages.${pkgs.stdenv.hostPlatform.system}.codex-reply;
  user-home = "/home/${cfg.user}";
  wecom-config = "${user-home}/.config/codex-reply/wecom.json";
in {
  systemd = {
    # The app-server it talks to is a home-manager *user* service (see
    # hosts/dt-w01/home-manager/default.nix), which is why this unit no longer
    # orders itself after it: the socket lives in the user's home and the relay
    # connects lazily per turn, reporting a failed injection if the server is
    # down. Cross-scope After/Wants is not expressible from a system unit.
    services.codex-reply = {
      description = "企业微信智能机器人长连接：投递 codex-notify 路由好的通知，并把用户回复注入本地 app-server";
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
