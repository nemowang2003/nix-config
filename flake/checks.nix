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
        audio-transcribe-uv-lock = inputs.audio-transcribe.checks.${pkgs.stdenv.hostPlatform.system}.uv-lock;
        llama-on-demand-cli = inputs.llama-on-demand.checks.${pkgs.stdenv.hostPlatform.system}.cli;
        llama-on-demand-unit = inputs.llama-on-demand.checks.${pkgs.stdenv.hostPlatform.system}.unit;
        codex-mutable-config = let
          valid = lib.all (home: let
            c = home.config;
            codex = c.my.codex;
            mutable-targets = lib.concatMap (directory:
              map (name: "${lib.removePrefix "${c.home.homeDirectory}/" directory}/${name}")
              (["config.toml"] ++ map (name: "${name}.config.toml") (lib.attrNames codex.profiles)))
            codex.home-directories;
          in
            !codex.enable || lib.all (file: !file.enable || !(lib.elem file.target mutable-targets)) (lib.attrValues c.home.file)) (lib.attrValues self.homeConfigurations);
        in
          assert lib.assertMsg valid "Codex mutable TOML files must not be installed as Home Manager symlinks";
            pkgs.runCommand "codex-mutable-config" {} ''
              touch "$out"
            '';
        host-eval = assert builtins.deepSeq ([self.user-pubkeys] ++ host-evaluations) true;
          pkgs.runCommand "host-eval" {} ''
            touch "$out"
          '';
      };
  };
}
