{...}: {
  nix.enable = false;
  system.activationScripts.postActivation.text = ''
    echo "restarting determinate nix daemon ..."
    launchctl kickstart -k system/systems.determinate.nix-daemon
  '';
}
