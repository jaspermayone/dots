
{ config, pkgs, ... }:

{
  imports = [
    ../../modules/common/system.nix
    ../../modules/users/jsp.nix
  ];

  # Necessary for using flakes on this system.
  nix.settings.experimental-features = "nix-command flakes";

  # Set Git commit hash for darwin-version.
  # Used for backwards compatibility, please read the changelog before changing.
  # $ darwin-rebuild changelog
  system.stateVersion = 6;

  # Machine-specific settings
  nixpkgs.hostPlatform = "aarch64-darwin"; # or "x86_64-darwin" for Intel

  environment.systemPackages = with pkgs; [
    docker
  ];

  system.defaults = {
  };

  # Hostname for this machine
  networking.hostName = "remus";

  # Set Git commit hash for darwin-version
  system.configurationRevision = self.rev or self.dirtyRev or null;

}