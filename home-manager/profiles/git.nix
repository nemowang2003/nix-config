{
  config,
  lib,
  pkgs,
  ...
}: {
  # git
  programs.git = {
    enable = true;
    ignores =
      [
        ".helix"
      ]
      ++ lib.optionals pkgs.stdenv.isDarwin [".DS_Store"];
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

  home.shellAliases = {
    g = "git";
    ga = "git add";
    gb = "git branch";
    gba = "git branch --all";
    gco = "git checkout";
    gc = "git commit --verbose";
    "gc!" = "git commit --verbose --amend";
    gca = "git commit --verbose --all";
    gcan = "git commit --verbose --all --no-edit";
    "gca!" = "git commit --verbose --all --amend";
    "gcan!" = "git commit --verbose --all --amend --no-edit";
    gcn = "git commit --verbose --no-edit";
    "gcn!" = "git commit --verbose --no-edit --amend";
    gd = "git diff";
    gdca = "git diff --cached";
    gdcw = "git diff --cached --word-diff";
    gds = "git diff --staged";
    gdw = "git diff --word-diff";
    gfa = "git fetch --all --tags --prune --jobs=10";
    gl = "git pull";
    "gl!" = "git pull --autostash";
    glg = "git log --stat";
    glgg = "git log --graph";
    gp = "git push";
    gpf = "git push --force-with-lease --force-if-includes";
    "gpf!" = "git push --force";
    grb = "git rebase";
    grba = "git rebase --abort";
    grbc = "git rebase --continue";
    grbi = "git rebase --interactive";
    grf = "git reflog";
    gr = "git remote";
    grv = "git remote --verbose";
    gra = "git remote add";
    grrm = "git remote remove";
    grmv = "git remote rename";
    grs = "git restore";
    grst = "git restore --staged";
    gst = "git status";
    gsta = "git stash push";
    gstaa = "git stash push --all";
    gstp = "git stash pop";
    "gstp!" = "git stash apply";
    gstd = "git stash drop";
    gsts = "git stash show --patch";
    gstl = "git stash list";
    gsw = "git switch";
    gswc = "git switch --create";
  };
}
