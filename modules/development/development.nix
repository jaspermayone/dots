{ config, pkgs, ... }:

{
  home.packages = with pkgs; [
    nodejs_20
    python3
    docker
  ];

  programs.zsh.shellAliases = {
    dc = "docker compose";
    dps = "docker ps";
  };
}