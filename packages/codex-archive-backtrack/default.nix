{
  python-application,
  pkgs,
  uv2nix,
  pyproject-nix,
  pyproject-build-systems,
}:
python-application {
  inherit pkgs uv2nix pyproject-nix pyproject-build-systems;
  root = ./.;
  name = "codex-archive-backtrack";
}
