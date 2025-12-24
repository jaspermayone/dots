# Remus - MacBook Pro M4
{ config, pkgs, lib, inputs, hostname, ... }:

{
  # Host-specific overrides go here
  # Most configuration is inherited from darwin/default.nix and home/default.nix

  # Agenix secrets for bore client
  age.secrets.bore-token = {
    file = ../../secrets/bore-token.age;
    path = "/Users/jsp/.config/bore/token";
    owner = "jsp";
    mode = "400";
  };

  # Remus-specific homebrew casks
  homebrew.casks = [
    # Add Mac apps specific to your laptop
    # "raycast"
    # "arc"
    # "1password"
  ];

  # Any remus-specific system defaults
  # system.defaults = { };

  # Set the hostname
  networking.hostName = "remus";
  networking.computerName = "Remus";
}
