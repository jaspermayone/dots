# Remus - MacBook Pro M4 (dev laptop)
{ config, pkgs, lib, inputs, hostname, ... }:

{
  # Host-specific overrides go here
  # Most configuration is inherited from darwin/default.nix and home/default.nix

  # Agenix identity path (use user SSH key on macOS)
  age.identityPaths = [ "/Users/jsp/.ssh/id_ed25519" ];

  # Agenix secrets for bore client
  age.secrets.bore-token = {
    file = ../../secrets/bore-token.age;
    path = "/Users/jsp/.config/bore/token";
    owner = "jsp";
    mode = "400";
  };

  # Atuin encryption key for auto-login
  age.secrets.atuin-key = {
    file = ../../secrets/atuin-key.age;
    path = "/Users/jsp/.local/share/atuin/key";
    owner = "jsp";
    mode = "400";
  };

  # Laptop-specific nix packages
  environment.systemPackages = with pkgs; [
    yubikey-manager
  ];

  # Laptop-specific homebrew packages
  homebrew.brews = [
    # Embedded development
    "arm-none-eabi-gcc"
    "dfu-util"
    "open-ocd"
    "stlink"
  ];

  # Remus-specific homebrew casks
  homebrew.casks = [
    "basictex"
    "gitkraken-cli"
  ];

  # Set the hostname
  networking.hostName = "remus";
  networking.computerName = "Remus";
}
