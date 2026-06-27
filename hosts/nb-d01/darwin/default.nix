{...}: {
  networking.computerName = "Ian's MacBook Air";

  homebrew.casks = [
    "android-platform-tools"
    "bitwarden"
    "obs"
    "obsidian"
    "qq"
    "steam"
    "tencent-meeting"
    "visual-studio-code"
    "wechat"
    "windows-app"
    "wpsoffice-cn"
  ];

  system.stateVersion = 6;
}
