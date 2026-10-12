{
  python-application,
  pkgs,
  pyproject-nix,
}: let
  application = python-application {
    inherit pkgs pyproject-nix;
    root = ./.;
  };
in
  application.overrideAttrs (old: {
    nativeBuildInputs = (old.nativeBuildInputs or []) ++ [pkgs.makeWrapper];
    postInstall =
      (old.postInstall or "")
      + ''
        substituteInPlace "$out/share/zsh/site-functions/_codex-notify" \
          --replace-fail '@sqlite3@' '${pkgs.lib.getExe pkgs.sqlite}' \
          --replace-fail '@jq@' '${pkgs.lib.getExe pkgs.jq}'
      '';
    postFixup =
      (old.postFixup or "")
      + ''
        wrapProgram "$out/bin/codex-notify" --set CODEX_NOTIFY_FZF ${pkgs.lib.getExe pkgs.fzf}
      '';
  })
