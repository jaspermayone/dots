# Darwin (macOS) specific configuration
{
  config,
  pkgs,
  lib,
  inputs,
  hostname,
  ...
}:

{
  # Nix configuration
  nix.settings.experimental-features = [
    "nix-command"
    "flakes"
  ];

  # Fix GID mismatch for nixbld group (new installs use 350, old used 30000)
  ids.gids.nixbld = 350;

  # Allow unfree packages
  nixpkgs.config.allowUnfree = true;

  # Primary user (required for homebrew and other user-specific options)
  system.primaryUser = "jsp";

  # System-level packages available to all users
  environment.systemPackages = with pkgs; [
    vim
    git
    inputs.agenix.packages.${pkgs.stdenv.hostPlatform.system}.default

    # CLI tools (migrated from homebrew)
    coreutils
    moreutils
    findutils
    git-lfs
    gnupg
    gnugrep
    openssh
    screen
    zsh
    ffmpeg
    imagemagick
    wget
    woff2

    # Additional CLI tools
    lazygit
    redis
    mkcert
    inetutils # telnet, ftp, etc.
    watchman
    pipx
    pwgen
    ninja
    gnumake
    ghostscript
    bitwarden-cli
    git-filter-repo
    libyaml
    fswatch
    wireguard-tools
  ];

  # Homebrew integration
  homebrew = {
    enable = true;
    onActivation = {
      autoUpdate = true;
      cleanup = "zap"; # Remove unlisted packages
      upgrade = true;
    };

    taps = [
      "bramstein/webfonttools"
      "charmbracelet/tap"
      "heroku/brew"
      "jaspermayone/tap"
      "minio/stable"
      "oven-sh/bun"
      "sst/tap"
      "stripe/stripe-cli"
      "withgraphite/tap"
      "dotenvx/brew"
    ];

    # CLI tools (only macOS-specific, special taps, or unavailable in nixpkgs)
    brews = [
      # macOS specific
      "mas" # Mac App Store CLI
      "libyaml" # Required for mise-installed Ruby (psych gem)

      # Font tools (bramstein tap)
      "sfnt2woff"
      "sfnt2woff-zopfli"

      # Cloud/Dev CLIs (from taps)
      "heroku/brew/heroku"
      "slack-cli"
      "stripe/stripe-cli/stripe"
      "vercel-cli"
      "withgraphite/tap/graphite"
      "sst/tap/opencode"
      "dotenvx/brew/dotenvx"

      # Charmbracelet tools
      "charmbracelet/tap/freeze"
      "charmbracelet/tap/crush"

      # Custom/personal
      "jaspermayone/tap/boxcar"
      "minio/stable/mc"

      # Build tools
      "ccache"
      "sccache"

      # Languages/runtimes (specific versions)
      "composer"
      "openjdk"
      "openjdk@21"
      "rust" # Keep for toolchain management

      # Databases (specific versions)
      "mysql@8.0"
      "postgresql@17"
      "percona-toolkit"
      "pgvector"

      # Image processing
      "vips"
      "graphicsmagick"

      # Misc tools
      "thefuck"
      "trufflehog"
      "eget"
      "gitmoji"
      "create-dmg"
    ];

    # GUI apps (casks) - shared across all Darwin machines
    casks = [
      "bitwarden"
      "discord"
      "espanso"
      "ngrok"
      "raycast"
      "slack"
    ];

    # Mac App Store apps (requires `mas` CLI)
    # masApps = {
    # "Xcode" = 497799835;
    # };
  };

  # macOS system preferences
  system.defaults = {
    # Global preferences
    NSGlobalDomain = {
      # Mouse/scrolling
      AppleEnableMouseSwipeNavigateWithScrolls = false;
      AppleEnableSwipeNavigateWithScrolls = false;

      # Auto-corrections
      NSAutomaticCapitalizationEnabled = false;
      NSAutomaticDashSubstitutionEnabled = false;
      NSAutomaticInlinePredictionEnabled = false;
      NSAutomaticPeriodSubstitutionEnabled = false;
      NSAutomaticQuoteSubstitutionEnabled = false;
      NSAutomaticSpellingCorrectionEnabled = false;

      # Interface
      AppleInterfaceStyle = "Dark";
      AppleICUForce24HourTime = false;
      _HIHideMenuBar = false;

      # Keyboard
      InitialKeyRepeat = 15;
      KeyRepeat = 2;
      ApplePressAndHoldEnabled = false;
      AppleKeyboardUIMode = 3; # Full keyboard access

      # Scrolling
      "com.apple.swipescrolldirection" = false; # (true = Natural scrolling

      # Appearance
      AppleShowAllExtensions = true;
      NSTableViewDefaultSizeMode = 1;

      # Units
      AppleMeasurementUnits = "Inches";
      AppleMetricUnits = 0;
      AppleTemperatureUnit = "Fahrenheit";

      # Window behavior
      NSWindowResizeTime = 0.001; # Faster window resize
      NSNavPanelExpandedStateForSaveMode = true; # Expand save panel
      NSNavPanelExpandedStateForSaveMode2 = true;
      PMPrintingExpandedStateForPrint = true; # Expand print panel
      PMPrintingExpandedStateForPrint2 = true;
      NSDocumentSaveNewDocumentsToCloud = false; # Save to disk, not iCloud
      NSDisableAutomaticTermination = true; # Prevent auto-termination of apps
    };

    # Finder
    finder = {
      AppleShowAllExtensions = true;
      AppleShowAllFiles = false;
      CreateDesktop = true;
      FXEnableExtensionChangeWarning = false;
      FXPreferredViewStyle = "clmv"; # Column view
      QuitMenuItem = true;
      ShowPathbar = true;
      ShowStatusBar = true;
      _FXShowPosixPathInTitle = true;
      # Desktop icons
      ShowExternalHardDrivesOnDesktop = false;
      ShowHardDrivesOnDesktop = false;
      ShowMountedServersOnDesktop = false;
      ShowRemovableMediaOnDesktop = false;
      # Sorting and search
      _FXSortFoldersFirst = true;
      FXDefaultSearchScope = "SCcf"; # Search current folder
    };

    # Screenshots
    screencapture = {
      disable-shadow = true;
      type = "png";
    };

    # Screen saver / lock
    screensaver = {
      askForPassword = true;
      askForPasswordDelay = 0;
    };

    # Menu bar clock
    menuExtraClock = {
      Show24Hour = true;
      ShowDayOfMonth = true;
      ShowDayOfWeek = true;
      ShowSeconds = false;
    };

    # Dock
    dock = {
      autohide = true; # Auto-hide the dock when not in use
      autohide-delay = 0.0; # Delay before dock appears on hover (0 = instant)
      mineffect = "scale"; # Minimize animation: "scale" or "genie"
      minimize-to-application = false; # Minimize windows into app icon vs separate dock item
      mru-spaces = false; # Rearrange spaces based on most recent use
      orientation = "left"; # Dock position: "left", "bottom", or "right"
      show-recents = false; # Show recently used apps in separate dock section
      tilesize = 48; # Icon size in pixels
      launchanim = false; # Animate app launch (bouncing icon)
      expose-animation-duration = 0.1; # Mission Control animation speed (lower = faster)
      showhidden = false; # Dim hidden app icons (Cmd+H) to show they're hidden
    };

    # Trackpad
    trackpad = {
      Clicking = true; # Tap to click
      TrackpadRightClick = true;
      TrackpadThreeFingerDrag = true;
      Dragging = true;
    };

    # Spaces
    spaces = {
      spans-displays = false;
    };

    # Window Manager (Stage Manager)
    WindowManager = {
      EnableStandardClickToShowDesktop = false;
      EnableTiledWindowMargins = false;
      GloballyEnabled = false;
    };

    # Login window
    loginwindow = {
      GuestEnabled = false;
    };

    # Custom settings
    CustomUserPreferences = {
      # System sound
      "com.apple.systemsound" = {
        "com.apple.sound.uiaudio.enabled" = 0; # Disable boot sound
      };

      # Help Viewer non-floating
      "com.apple.helpviewer" = {
        DevMode = true;
      };

      # Disable "Are you sure you want to open this application?" dialog
      "com.apple.LaunchServices" = {
        LSQuarantine = false;
      };

      # Disable Resume system-wide
      "com.apple.systempreferences" = {
        NSQuitAlwaysKeepsWindows = false;
      };

      # Printer: quit when finished
      "com.apple.print.PrintingPrefs" = {
        "Quit When Finished" = true;
      };

      # Finder extras
      "com.apple.finder" = {
        ShowRecentTags = false;
        OpenWindowForNewRemovableDisk = true; # Auto-open for mounted volumes
      };

      # Disk images: skip verification
      "com.apple.frameworks.diskimages" = {
        skip-verify = true;
        skip-verify-locked = true;
        skip-verify-remote = true;
      };

      # Dock spring loading
      "com.apple.dock" = {
        "springboard-show-duration" = 0;
      };

      # Safari
      "com.apple.Safari" = {
        UniversalSearchEnabled = false; # Don't send search queries to Apple
        SuppressSearchSuggestions = true;
        ShowFullURLInSmartSearchField = true;
        HomePage = "about:blank";
        IncludeDevelopMenu = true;
        WebKitDeveloperExtrasEnabledPreferenceKey = true;
        "com.apple.Safari.ContentPageGroupIdentifier.WebKit2DeveloperExtrasEnabled" = true;
        WarnAboutFraudulentWebsites = true;
        SendDoNotTrackHTTPHeader = true;
      };

      # Mail
      "com.apple.mail" = {
        AddressesIncludeNameOnPasteboard = false; # Copy addresses without name
        NSUserKeyEquivalents = {
          Send = "@\\U21a9"; # Cmd+Enter to send
        };
        DisableInlineAttachmentViewing = true;
      };

      # Terminal
      "com.apple.terminal" = {
        StringEncodings = [ 4 ]; # UTF-8 only
      };

      # iTerm2
      "com.googlecode.iterm2" = {
        PromptOnQuit = false;
      };

      # Time Machine
      "com.apple.TimeMachine" = {
        DoNotOfferNewDisksForBackup = true;
      };

      # Activity Monitor
      "com.apple.ActivityMonitor" = {
        OpenMainWindow = true;
        ShowCategory = 0; # All processes
        SortColumn = "CPUUsage";
        SortDirection = 0;
      };

      # TextEdit
      "com.apple.TextEdit" = {
        RichText = 0; # Plain text mode
        PlainTextEncoding = 4; # UTF-8
        PlainTextEncodingForWrite = 4;
      };

      # Disk Utility
      "com.apple.DiskUtility" = {
        DUDebugMenuEnabled = true;
        "advanced-image-options" = true;
      };

      # Mac App Store
      "com.apple.appstore" = {
        ShowDebugMenu = true;
        WebKitDeveloperExtras = true;
      };

      # Software Update
      "com.apple.SoftwareUpdate" = {
        AutomaticCheckEnabled = true;
        ScheduleFrequency = 1; # Daily
        AutomaticDownload = 1;
        CriticalUpdateInstall = 1; # Auto-install security updates
        AutoUpdate = true;
      };

      # Don't write .DS_Store files on network or USB volumes
      "com.apple.desktopservices" = {
        DSDontWriteNetworkStores = true;
        DSDontWriteUSBStores = true;
      };

      # Photos: don't open automatically
      "com.apple.ImageCapture" = {
        disableHotPlug = true;
      };

      # Messages
      "com.apple.messageshelper.MessageController" = {
        SOInputLineSettings = {
          automaticQuoteSubstitutionEnabled = false;
        };
      };
      "com.apple.messages.text" = {
        NSAutomaticSpellingCorrectionEnabled = false;
      };
    };
  };

  # Activation scripts for settings that can't be done declaratively
  # Note: these run as root during activation
  system.activationScripts.extraActivation.text = ''
    # Symlink nix bitwarden-cli to homebrew bin for Raycast compatibility
    ln -sf /run/current-system/sw/bin/bw /opt/homebrew/bin/bw

    # Show ~/Library folder (for primary user)
    chflags nohidden /Users/jsp/Library

    # Show /Volumes folder
    chflags nohidden /Volumes

    # Power management settings
    # Wake on lid open
    pmset -a lidwake 1
    # Display sleep: 15 min on power, 5 min on battery
    pmset -c displaysleep 15
    pmset -b displaysleep 5
    # Disable sleep while charging (system sleep never on AC)
    pmset -c sleep 0
    # 24-hour delay before standby (in seconds: 86400)
    pmset -a standbydelay 86400

    # Enable HiDPI display modes
    defaults write /Library/Preferences/com.apple.windowserver DisplayResolutionEnabled -bool true
  '';

  # Enable Touch ID for sudo
  security.pam.services.sudo_local.touchIdAuth = true;

  # Create /etc/zshrc that loads nix-darwin environment
  programs.zsh.enable = true;

  # Fonts
  fonts.packages = with pkgs; [
    nerd-fonts.jetbrains-mono
    nerd-fonts.fira-code
  ];

  # Used for backwards compatibility
  system.stateVersion = 4;
}
