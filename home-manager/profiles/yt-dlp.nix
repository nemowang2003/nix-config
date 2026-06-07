{pkgs, ...}: {
  home.packages = [pkgs.aria2];

  programs.yt-dlp = {
    enable = true;

    settings = {
      downloader = "aria2c";
      downloader-args = "aria2c:'-x 16 -k 20M -s 16'";
      impersonate = "chrome";
    };
  };
}
