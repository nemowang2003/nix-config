{lib, ...}: {
  isDarwin = arch: (lib.systems.elaborate arch).isDarwin;
  isLinux = arch: (lib.systems.elaborate arch).isLinux;
}
