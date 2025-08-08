{ pkgs, ... }:
{
  services.cron = {
    enable = true;
    systemCronJobs = [
      # Verify cron is working
      "* * * * *  jsp date > /tmp/latest-cron.log"
      # Regularly fetch latest dotfiles from GitHub
      "0 * * * *  jsp ${pkgs.git} --git-dir /Users/jsp/dots/.git fetch --all"
    ];
  };
}