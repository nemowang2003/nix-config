{self, ...}: {
  imports =
    [
    ]
    ++ self.lib.collect-nix-files ./modules
    ++ self.lib.collect-nix-files ./profiles;
}
