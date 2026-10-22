{...}: {
  networking.computerName = "Ian's MacBook Air";

  homebrew.casks = [
    "bitwarden"
    "obs"
    "obsidian"
    "qq"
    "steam"
    "tencent-meeting"
    "uuremote"
    "visual-studio-code"
    "wechat"
    "windows-app"
    "wpsoffice-cn"
  ];

  system.stateVersion = 6;
}
