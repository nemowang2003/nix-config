{
  self,
  lib,
  pkgs,
  hostname,
  cfg,
  ...
}: {
  imports = self.lib.collect-nix-files ./profiles;

  config = lib.mkMerge [
    (self.build-nix-settings cfg)
    {
      networking = {
        hostName = hostname;
        localHostName = hostname;
      };

      environment.shells = [pkgs.zsh];

      users.users.${cfg.user} = {
        name = cfg.user;
        home = "/Users/${cfg.user}";
        openssh.authorizedKeys.keys = self.user-pubkeys;
      };

      system = {
        primaryUser = cfg.user;
        defaults = {
          # TODO
        };
      };

      programs.zsh = {
        enableBashCompletion = false;
        enableCompletion = false;
        promptInit = "";
      };

      security.pam.services.sudo_local.touchIdAuth = true;
    }
  ];
}
