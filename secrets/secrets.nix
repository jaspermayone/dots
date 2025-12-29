# Agenix secrets configuration
#
# This file declares which SSH keys can decrypt which secrets.
# Run `agenix -e <secret>.age` to create/edit secrets.

let
  # User SSH public keys
  jsp = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIHm7lo7umraewipgQu1Pifmoo/V8jYGDHjBTmt+7SOCe jsp@remus";

  # Host SSH public keys
  alastor = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIFwkC1CiWpLB10NNVaJwu4LSyiL0wM7ExI1VoKqIsgeG root@alastor-vnic";
  dippet = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIOqi0ZRAHUqBL4zolSeVTgp1oZ6HKD+Hq5AktpLolely jsp@Dippet";

  # Groups for convenience
  allUsers = [ jsp ];
  allHosts = [ alastor  dippet ];
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

  "pds.age".publicKeys = [ jsp alastor ];

  # If using Resend SMTP, include API key here too
  "pds-mailer.age".publicKeys = [ jsp alastor ];


  # WiFi passwords for NixOS machines
  # Format: NETWORK_PSK=password
  "wifi-passwords.age".publicKeys = all;

  # GitHub token for knot-sync service
  # Format: GITHUB_TOKEN=ghp_xxxxx
  "github-token.age".publicKeys = all;

  # Atuin encryption key for sync
  # Contains the raw encryption key for Atuin shell history sync
  "atuin-key.age".publicKeys = all;

  # Espanso secrets (sensitive text expansions)
  # Contains: email addresses, EINs, personal addresses
  "espanso-secrets.age".publicKeys = all;

  # Wakatime API key
  # Format: api_key = xxxxx
  "wakatime-api-key.age".publicKeys = all;

  # NPM registry tokens
  # Contains: npmjs.org and GitHub packages auth tokens
  "npmrc.age".publicKeys = all;
}
