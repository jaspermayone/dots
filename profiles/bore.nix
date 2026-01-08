# Bore tunnel client configuration
{
  config,
  lib,
  pkgs,
  ...
}:

{
  imports = [ ../modules/bore ];

  atelier.bore = {
    enable = true;
    serverAddr = "tun.hogwarts.channel";
    serverPort = 7000;
    domain = "tun.hogwarts.channel";
    authTokenFile =
      if pkgs.stdenv.isDarwin then "/Users/jsp/.config/bore/token" else "/home/jsp/.config/bore/token";
  };
}
