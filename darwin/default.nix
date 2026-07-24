{
  self,
  lib,
  pkgs,
  hostname,
  cfg,
  ...
}: {
  imports = self.lib.collect-nix-files ./profiles;

  config = lib.mkMerge [
    (self.build-nix-settings cfg)
    {
      networking = {
        hostName = hostname;
        localHostName = hostname;
      };

      environment.shells = [pkgs.zsh];

      users.users.${cfg.user} = {
        name = cfg.user;
        home = "/Users/${cfg.user}";
        openssh.authorizedKeys.keys = self.user-pubkeys;
      };

      system = {
        primaryUser = cfg.user;
        defaults = {
          NSGlobalDomain = {
            AppleShowAllExtensions = true;
            NSAutomaticCapitalizationEnabled = false;
            NSAutomaticPeriodSubstitutionEnabled = false;
            "com.apple.trackpad.forceClick" = false;
            "com.apple.trackpad.scaling" = 1.5;
          };

          dock = {
            mineffect = "scale";
            minimize-to-application = true;
            mru-spaces = false;
            show-recents = false;
            showDesktopGestureEnabled = false;
            tilesize = 61;
            wvous-bl-corner = 11; # Launchpad
            wvous-br-corner = 14; # Quick Note
          };

          finder = {
            FXPreferredViewStyle = "Nlsv";
            NewWindowTarget = "Other";
            NewWindowTargetPath = "file:///Users/${cfg.user}/Downloads/";
            ShowExternalHardDrivesOnDesktop = false;
            ShowPathbar = true;
            ShowRemovableMediaOnDesktop = false;
          };

          screencapture.location = "/Users/${cfg.user}/Downloads";

          WindowManager = {
            AppWindowGroupingBehavior = true;
            EnableStandardClickToShowDesktop = false;
            EnableTiledWindowMargins = false;
            GloballyEnabled = true;
            HideDesktop = true;
            StageManagerHideWidgets = true;
          };

          trackpad = {
            Clicking = true;
            TrackpadRightClick = true;
            TrackpadThreeFingerDrag = true;
          };

          menuExtraClock = {
            ShowAMPM = true;
            ShowDayOfWeek = true;
          };
        };
      };

      programs.zsh = {
        enableBashCompletion = false;
        enableCompletion = false;
        promptInit = "";
      };

      security.pam.services.sudo_local.touchIdAuth = true;
    }
  ];
}
