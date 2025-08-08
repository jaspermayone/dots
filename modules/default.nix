{ ... }:

{
  # Development tools and configurations
  development = {
    core = ./development/development.nix;
    git = ./development/git.nix;
    vscode-server = ./development/vscode-server.nix;
  };

  # System-level configurations
  system = {
    core = ./system/system.nix;
    shell = ./system/zsh.nix;
    networking = ./system/dig.nix;
  };

  # User configurations and settings
  users = {
    jsp = ./users/jsp.nix;
    home = ./users/home.nix;
    ssh_keys = ./users/ssh_keys.nix;
  };

  # Background services
  services = {
    cron = ./services/cron.nix;
  };
}