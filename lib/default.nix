{
  inputs,
  lib,
}: {
  collect-nix-files = src:
    lib.filter
    (path: lib.hasSuffix ".nix" (toString path))
    (lib.filesystem.listFilesRecursive src);
}
