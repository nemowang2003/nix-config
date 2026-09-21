{self, ...}: {
  perSystem = {
    pkgs,
    lib,
    ...
  }: let
    mk-python-test = {
      name,
      python,
      source,
    }:
      pkgs.runCommand name {
        nativeBuildInputs = [python];
      } ''
        export PYTHONDONTWRITEBYTECODE=1
        cd ${source}
        python test_main.py
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
        python = pkgs.python314.withPackages (ps: [ps.httpx]);
        source = ../packages/codex-notify;
      };

      codex-wecom-relay-tests = mk-python-test {
        name = "codex-wecom-relay-tests";
        python = pkgs.python314.withPackages (ps: [ps.websockets]);
        source = ../packages/codex-wecom-relay;
      };

      codex-archive-backtrack-tests = mk-python-test {
        name = "codex-archive-backtrack-tests";
        python = pkgs.python314;
        source = ../packages/codex-archive-backtrack;
      };
    };
  };
}
