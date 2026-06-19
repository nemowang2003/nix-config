{lib, ...}: let
  extraSubstituters = [
    "https://nix-community.cachix.org"
    "https://helix.cachix.org"
  ];
  extraTrustedPublicKeys = [
    "nix-community.cachix.org-1:mB9FSh9qf2dCimDSUo8Zy7bkq5CX+/rkCWyvRCYg3Fs="
    "helix.cachix.org-1:ejp9KQpR1FBI2onstMQ34yogDm4OgU2ru6lIwPvuCVs="
  ];
in {
  flake.nixCache = {
    inherit extraSubstituters extraTrustedPublicKeys;

    customConf = ''
      extra-substituters = ${lib.concatStringsSep " " extraSubstituters}
      extra-trusted-public-keys = ${lib.concatStringsSep " " extraTrustedPublicKeys}
    '';
  };
}
