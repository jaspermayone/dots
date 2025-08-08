{
  # Forest is connected to the internet on DO, so don't trust it for SSH by default
  # forest = ''
  #   ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAID/BUnY1AysGsBsjqQOyC4wKjlmar5yCLXy9pInYMtcc msw@forest
  # '';
  remus = ''
    ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIHm7lo7umraewipgQu1Pifmoo/V8jYGDHjBTmt+7SOCe jsp@remus
  '';
  pb-01-core = ''
    ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAICLWCzzB2Fj/XiuWo5PnZBcXs0wxUlbAN+c4bX8auv6g jsp@pb-01-core
  '';
}