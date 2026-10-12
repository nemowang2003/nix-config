{
  self,
  inputs,
  ...
}: {
  perSystem = {
    pkgs,
    lib,
    ...
  }: let
    package-tests =
      lib.concatMapAttrs
      (name: package:
        lib.mapAttrs'
        (test-name: test: lib.nameValuePair "${name}-${test-name}" test)
        (package.passthru.tests or {}))
      self.packages.${pkgs.stdenv.hostPlatform.system};
    host-evaluations = lib.concatLists (
      lib.mapAttrsToList
      (hostname: host:
        [self.homeConfigurations."${host.user}@${hostname}".config.home.stateVersion]
        ++ lib.optional host.isDarwin self.darwinConfigurations.${hostname}.config.system.stateVersion
        ++ lib.optional (host.isLinux && host.platform != "generic") self.nixosConfigurations.${hostname}.config.system.stateVersion
        ++ lib.optional (host.platform == "generic") self.genericConfigurations.${hostname}.config.system.build.activationPackage.drvPath)
      self.hosts
    );
  in {
    checks =
      package-tests
      // {
        llama-on-demand-proxy-import = inputs.llama-on-demand.checks.${pkgs.stdenv.hostPlatform.system}.proxy-import;
        llama-on-demand-unit = inputs.llama-on-demand.checks.${pkgs.stdenv.hostPlatform.system}.unit;
        host-eval = assert builtins.deepSeq ([self.user-pubkeys] ++ host-evaluations) true;
          pkgs.runCommand "host-eval" {} ''
            touch "$out"
          '';
      };
  };
}
