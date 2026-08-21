{pkgs, ...}:
pkgs.writeShellApplication {
  name = "generic-rebuild";
  runtimeInputs = [pkgs.nix];
  text = ''
    set -euo pipefail

    action=switch
    flake=''${PRJ_ROOT:-.}
    while [[ $# -gt 0 ]]; do
      case "$1" in
        --flake)
          flake=$2
          shift 2
          ;;
        build | switch)
          action=$1
          shift
          ;;
        *)
          echo "usage: generic-rebuild [build|switch] [--flake <flake>]" >&2
          exit 1
          ;;
      esac
    done

    host="$(hostname -s)"
    attr="$flake#genericConfigurations.$host.config.system.build.activationPackage"

    case "$action" in
      build)
        nix build --no-link --print-out-paths "$attr"
        ;;
      switch)
        if (( EUID != 0 )); then
          echo "generic-rebuild: system activation must be run as root" >&2
          exit 1
        fi

        activation="$(nix build --no-link --print-out-paths "$attr")"
        exec "$activation/bin/generic-system-activate"
        ;;
    esac
  '';
}
