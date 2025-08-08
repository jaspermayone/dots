{ config, pkgs, ... }:

{
  imports = [
    ../../modules/common/home.nix
    ../../modules/programs/development.nix
    ../../modules/programs/git.nix
    ../../modules/programs/zsh.nix
  ];

  home = {
    username = "jsp";
    homeDirectory = "/Users/jsp";
    stateVersion = "23.11";
  };

  # machine-specific packages
  home.packages = with pkgs; [
    slack
    zoom-us
    docker
    vscode
  ];

  # machine-specific shell aliases
  programs.zsh.shellAliases = {
  };

  # machine-specific git configuration
  programs.git.extraConfig = {
    # "url \"git@github.com:mlh/\"".insteadOf = "https://github.com/mlh-engineering/";
  };
}