{
  self,
  inputs,
  lib,
  hosts,
  ...
}: {
  flake = {
    deploy.nodes = lib.pipe hosts [
      (lib.filterAttrs (hostname: cfg: cfg.deploy))
      (
        lib.mapAttrs
        (hostname: cfg: {
          inherit hostname;
          profiles.home = {
            sshUser = cfg.user;
            user = cfg.user;
            path =
              inputs.deploy-rs.lib.${cfg.arch}.activate.home-manager
              self.homeConfigurations."${cfg.user}@${hostname}";
          };
        })
      )
    ];
  };
}
