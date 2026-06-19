{self, lib, ...}: {
  environment.etc."nix/nix.custom.conf".text = lib.mkAfter self.nixCache.customConf;
  system.activationScripts.postActivation.text = ''
    echo "restarting determinate nix daemon ..."
    launchctl kickstart -k system/systems.determinate.nix-daemon
  '';
}
