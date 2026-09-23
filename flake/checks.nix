{self, ...}: {
  perSystem = {
    pkgs,
    lib,
    ...
  }: let
    mk-python-test = {
      name,
      application,
      source,
    }:
      pkgs.runCommand name {} ''
        export PYTHONDONTWRITEBYTECODE=1
        cd ${source}
        export PYTHONPATH="$PWD/src"
        ${application.venv}/bin/python -m unittest discover -s tests
        touch "$out"
      '';
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
    checks = {
      host-eval = assert builtins.deepSeq ([self.user-pubkeys] ++ host-evaluations) true;
        pkgs.runCommand "host-eval" {} ''
          touch "$out"
        '';

      codex-notify-tests = mk-python-test {
        name = "codex-notify-tests";
        application = self.packages.${pkgs.stdenv.hostPlatform.system}.codex-notify;
        source = ../packages/codex-notify;
      };

      codex-wecom-relay-tests = mk-python-test {
        name = "codex-wecom-relay-tests";
        application = self.packages.${pkgs.stdenv.hostPlatform.system}.codex-wecom-relay;
        source = ../packages/codex-wecom-relay;
      };

      codex-archive-backtrack-tests = mk-python-test {
        name = "codex-archive-backtrack-tests";
        application = self.packages.${pkgs.stdenv.hostPlatform.system}.codex-archive-backtrack;
        source = ../packages/codex-archive-backtrack;
      };
    };
  };
}
