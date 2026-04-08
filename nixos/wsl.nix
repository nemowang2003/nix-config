{
  inputs,
  hostname,
  cfg,
  ...
}: {
  imports = [
    inputs.nixos-wsl.nixosModules.default
  ];

  wsl.enable = true;
  wsl.defaultUser = cfg.user;
}
