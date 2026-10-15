{
  config,
  lib,
  pkgs,
  self,
  ...
}: let
  user-home = config.home.homeDirectory;
  windows-path = lib.getExe self.packages.${pkgs.stdenv.hostPlatform.system}.wsl-windows-path;
  relay = pkgs.writeShellScript "codex-wecom-relay" ''
    export PATH="$PATH$(${windows-path})"
    exec ${lib.getExe self.packages.${pkgs.stdenv.hostPlatform.system}.codex-wecom-relay} "$@"
  '';
in {
  systemd.user.services.codex-wecom-relay = {
    Unit = {
      Description = "企业微信智能机器人长连接：投递 Codex 通知，并把回复注入对应 Codex home 的 daemon";
      Requires = ["sops-nix.service"];
      After = ["sops-nix.service"];
    };
    Service = {
      Type = "simple";
      WorkingDirectory = user-home;
      EnvironmentFile = "${config.xdg.configHome}/sops-nix/env/common";
      Environment = [
        "XDG_CACHE_HOME=${config.xdg.cacheHome}"
        "XDG_CONFIG_HOME=${config.xdg.configHome}"
        "XDG_STATE_HOME=${config.xdg.stateHome}"
      ];
      ExecStart = lib.escapeShellArgs (
        [
          relay
          "--config"
          "${config.xdg.configHome}/codex-wecom-relay/wecom.json"
          "--codex-bin"
          (lib.getExe config.my.codex.package)
        ]
        ++ lib.concatMap (home: ["--codex-home" home]) config.my.codex.home-directories
      );
      Restart = "on-failure";
      RestartSec = "5s";
      KillSignal = "SIGINT";
      TimeoutStopSec = "10s";
    };
    Install.WantedBy = ["default.target"];
  };

  my.codex.contexts = lib.mkAfter [
    ''
      ## dt-w01 host notes (NixOS WSL)

      This host runs NixOS on WSL. Use powershell.exe to run Windows commands
      instead of cmd.exe. Do not pass -NoProfile to powershell.exe: the user's
      profile sets the output encoding to UTF-8 so Chinese and other non-ASCII
      text is transmitted correctly. The profile automatically skips interactive
      decorations when output is redirected.

      To create symlinks, use PowerShell's
      `[NativeLinks]::CreateSymbolicLink($source, $dest, 3)`.
    ''
  ];
}
