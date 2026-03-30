# Home Manager configuration for the fundingfindr service user
{ ... }:

{
  home.username = "fundingfindr";
  home.homeDirectory = "/home/fundingfindr";
  home.stateVersion = "24.05";

  programs.home-manager.enable = true;

  programs.bash = {
    enable = true;
    shellAliases = {
      br = "set -a; source /etc/funding_findr/env; set +a; RAILS_ENV=production BUNDLE_PATH=vendor/bundle BUNDLE_WITHOUT=development:test RUBY_YJIT_ENABLE=1 bundle exec";
    };
  };
}
