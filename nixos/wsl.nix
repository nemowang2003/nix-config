{
  inputs,
  cfg,
  ...
}: {
  imports = [
    inputs.nixos-wsl.nixosModules.default
  ];

  wsl = {
    enable = true;
    defaultUser = cfg.user;
    useWindowsDriver = true;
  };
}
