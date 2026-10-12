{
  python-application,
  pkgs,
  pyproject-nix,
}:
python-application {
  inherit pkgs pyproject-nix;
  root = ./.;
}
