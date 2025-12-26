# Agenix secrets configuration
#
# This file declares which SSH keys can decrypt which secrets.
# Run `agenix -e <secret>.age` to create/edit secrets.

let
  # User SSH public keys (from ~/.ssh/id_ed25519.pub or similar)
  jsp = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIHm7lo7umraewipgQu1Pifmoo/V8jYGDHjBTmt+7SOCe jsp@remus";

  # Host SSH public keys (converted to age format with ssh-to-age)
  alastor = "age1ltqszzylcmcvdatezqagnpzyps8layutdq7fae8a672ys6feyadqdufecy";

  # Groups for convenience
  allUsers = [ jsp ];
  allHosts = [ alastor ];
  all = allUsers ++ allHosts;
in
{
  # frp authentication token (used by both server and clients)
  # This is the shared secret between frps and bore clients
  "frps-token.age".publicKeys = all;

  # Cloudflare API credentials for ACME DNS challenge
  # Format: CF_DNS_API_TOKEN=xxxxx
  "cloudflare-credentials.age".publicKeys = [ jsp alastor ];

  # Bore client token (same as frps-token, but separate file for clarity)
  # Used on client machines (remus, etc)
  "bore-token.age".publicKeys = all;

  # Tangled Knot server secret
  # Generate with: openssl rand -hex 32
  "knot-secret.age".publicKeys = all;

  # WiFi passwords for NixOS machines
  # Format: NETWORK_PSK=password
  "wifi-passwords.age".publicKeys = all;

  # GitHub token for knot-sync service
  # Format: GITHUB_TOKEN=ghp_xxxxx
  "github-token.age".publicKeys = all;
}
