{
  python-application,
  pkgs,
  pyproject-nix,
}:
(python-application {
  inherit pkgs pyproject-nix;
  root = ./.;
}).overrideAttrs (old: {
  postInstall =
    (old.postInstall or "")
    + ''
      install -Dm644 LICENSE "$out/share/licenses/2fa/LICENSE"
    '';
})
