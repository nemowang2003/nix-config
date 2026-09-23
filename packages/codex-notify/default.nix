{
  python-application,
  pkgs,
  uv2nix,
  pyproject-nix,
  pyproject-build-systems,
}: let
  application = python-application {
    inherit pkgs uv2nix pyproject-nix pyproject-build-systems;
    root = ./.;
    name = "codex-notify";
  };
in
  application.overrideAttrs (old: {
    nativeBuildInputs = (old.nativeBuildInputs or []) ++ [pkgs.makeWrapper];
    postFixup =
      (old.postFixup or "")
      + ''
        wrapProgram "$out/bin/codex-notify" --set CODEX_NOTIFY_FZF ${pkgs.lib.getExe pkgs.fzf}
      '';
  })
