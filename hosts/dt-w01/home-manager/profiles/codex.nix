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
      ExecStart = lib.escapeShellArgs [
        relay
        "--config"
        "${config.xdg.configHome}/codex-wecom-relay/wecom.json"
        "--codex-bin"
        (lib.getExe config.my.codex.package)
        "--codex-home"
        "${user-home}/.codex-openai"
        "--codex-home"
        "${user-home}/.codex-tca"
      ];
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

      本机是 NixOS WSL。需要调用 Windows 命令时使用 powershell.exe，不要用
      cmd.exe；并且不要给 powershell.exe 加 -NoProfile：用户 profile 会把输出
      编码设为 UTF-8，中文等非 ASCII 文本才能正确传递（输出被重定向时 profile
      里的交互式装饰会自动跳过）。

      需要创建 symlink 时，使用 PowerShell 的
      `[NativeLinks]::CreateSymbolicLink($source, $dest, 3)`。
    ''
  ];
}
