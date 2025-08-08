{ config, pkgs, ... }:

{
  # User account configuration
  users.users.jsp = {
    name = "jsp";
    home = "/Users/jsp";
    description = "@jaspermayone";
    shell = pkgs.zsh;  # Set default shell
    isNormalUser = true;
    extraGroups = [
      "wheel" # Enable 'sudo' for the user.
      "networkmanager"
    ];

    openssh.authorizedKeys.keys = builtins.attrValues(import ./ssh_keys.nix);
  };

  # Enable zsh system-wide (required for user shell)
  programs.zsh.enable = true;

  # User-specific system preferences
  system.defaults = {
    # Login and user session settings
    loginwindow = {
      GuestEnabled = false;
      SHOWFULLNAME = false;
    };

    # Security settings
    screensaver = {
      askForPassword = true;
      askForPasswordDelay = 0;
    };
  };

  # User directories and permissions
  system.activationScripts.userSetup.text = ''
    # Ensure user directories exist with proper permissions
    mkdir -p /Users/jsp/{Downloads,Documents,Desktop,Pictures}
    chown jsp:staff /Users/jsp/{Downloads,Documents,Desktop,Pictures}

    # Create common development directories
    mkdir -p /Users/jsp/{work,projects,scripts}
    chown jsp:staff /Users/jsp/{work,projects,scripts}

    # Ensure dots directory exists
    mkdir -p /Users/jsp/dots
    chown jsp:staff /Users/jsp/dots
  '';

  # User-specific environment variables (system-wide)
  environment.variables = {
    # Set default editor for all users but especially for jsp
    EDITOR = "nano";  # Use nano as the default editor
    VISUAL = "nano";
  };
}