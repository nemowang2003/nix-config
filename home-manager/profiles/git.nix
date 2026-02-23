{ config, lib, pkgs, ... }:

{
  programs.git = {
    enable = true;
    ignores = [
      
    ] ++ lib.optionals pkgs.stdenv.isDarwin [ ".DS_Store" ];
    settings = {
      user = {
        name = "nemowang";
        email = "nemowang@outlook.com";
        signingkey = "${config.home.homeDirectory}/.ssh/id_ed25519.pub";
      };
      core.quotepath = false;
      commit.gpgsign = true;
      gpg.format = "ssh";
      pull.rebase = true;
      push.autoSetupRemote = true;
      init.defaultBranch = "main";
    };
  };
}
