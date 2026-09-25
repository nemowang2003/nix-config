{cfg, ...}: {
  systemd = {
    # codex-openai-app-server, codex-tca-app-server, and codex-wecom-relay are
    # home-manager user services (see
    # hosts/dt-w01/home-manager/default.nix). Linger is what lets that manager
    # start at boot and keep running across WSL session teardown, e.g. for the
    # skyland-auto-sign daily user timer as well.
    tmpfiles.rules = [
      "f /var/lib/systemd/linger/${cfg.user} 0644 root root -"
    ];
  };

  system.stateVersion = "25.05";
}
