{pkgs, ...}:
# Deliberately resolve `nix` from the ambient PATH instead of injecting
# nixpkgs' nix: on generic hosts the daemon is Determinate Nix, installed
# out-of-band, and a mismatched client can misbehave. The devshell `rebuild`
# forwards the user PATH through `sudo env "PATH=$PATH"` so this script sees
# the system nix.
(pkgs.writeShellScriptBin "generic-rebuild" (builtins.readFile ./main.sh)).overrideAttrs (old: {
  nativeBuildInputs = (old.nativeBuildInputs or []) ++ [pkgs.installShellFiles];
  buildCommand =
    old.buildCommand
    + ''
      installShellCompletion --zsh ${./_generic-rebuild}
    '';
})
