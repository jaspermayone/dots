{ config, pkgs, ... }:

let
  modules = import ../../modules;
in
{
  imports = [
    modules.users.home
    modules.development.core
    modules.development.git
    modules.system.shell
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