{
  inputs,
  lib,
}: {
  force-shallow-transformer = cursor: mod:
    if cursor == []
    then mod
    else if mod ? default
    then mod.default
    else throw "packages/${lib.concatStringsSep "/" cursor} must be a top-level .nix file or a directory containing default.nix";
}
