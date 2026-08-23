{pkgs, ...}: {
  home.stateVersion = "25.11";

  # OL8 自带的 OpenSSH 8.0 不支持 ssh-keygen -Y，git SSH 签名改用
  # nixpkgs 的 ssh-keygen；ssh 传输仍走系统 OpenSSH。
  programs.git.settings.gpg.ssh.program = "${pkgs.openssh}/bin/ssh-keygen";
}
