{
  inputs,
  lib,
  cfg,
  ...
}: {
  imports = [
    inputs.determinate.darwinModules.default
  ];

  config = lib.mkIf cfg.determinate {
    system.activationScripts.postActivation.text = ''
      echo "restarting determinate nix daemon ..."
      launchctl kickstart -k system/systems.determinate.nix-daemon
    '';
  };
}
