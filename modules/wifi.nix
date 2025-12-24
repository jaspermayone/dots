# Simple NetworkManager WiFi module (NixOS only)
#
# Provides a simpler way to declare wifi profiles with NetworkManager.
# - Pass PSK via environment variable, direct value, or file
# - Supports eduroam networks with the `eduroam = true` flag
#
# Example usage:
#   jsp.network.wifi = {
#     enable = true;
#     profiles = {
#       "MySSID" = { psk = "supersecret"; };
#       "eduroam" = {
#         eduroam = true;
#         identity = "user@university.edu";
#         psk = "password";
#       };
#     };
#   };

{
  lib,
  config,
  pkgs,
  ...
}:
let
  cfg = config.jsp.network.wifi;
  mkProfile =
    name:
    {
      pskVar ? null,
      psk ? null,
      pskFile ? null,
      eduroam ? false,
      identity ? null,
    }:
    let
      base = {
        connection = {
          id = name;
          type = "wifi";
        };
        ipv4.method = "auto";
        ipv6 = {
          addr-gen-mode = "stable-privacy";
          method = "auto";
        };
        wifi = {
          mode = "infrastructure";
          ssid = name;
        };
      };
      sec =
        if eduroam then
          if pskVar != null then
            {
              wifi-security = {
                key-mgmt = "wpa-eap";
                password = "$" + pskVar;
                identity = identity;
                phase2-auth = "mschapv2";
              };
            }
          else if psk != null then
            {
              wifi-security = {
                key-mgmt = "wpa-eap";
                password = psk;
                identity = identity;
                phase2-auth = "mschapv2";
              };
            }
          else if pskFile != null then
            {
              wifi-security = {
                key-mgmt = "wpa-eap";
                password = "$(" + pkgs.coreutils + "/bin/cat " + pskFile + ")";
                identity = identity;
                phase2-auth = "mschapv2";
              };
            }
          else
            { }
        else if pskVar != null then
          {
            wifi-security = {
              key-mgmt = "wpa-psk";
              psk = "$" + pskVar;
            };
          }
        else if psk != null then
          {
            wifi-security = {
              key-mgmt = "wpa-psk";
              psk = psk;
            };
          }
        else if pskFile != null then
          {
            wifi-security = {
              key-mgmt = "wpa-psk";
              psk = "$(" + pkgs.coreutils + "/bin/cat " + pskFile + ")";
            };
          }
        else
          { };
    in
    base // sec;
in
{
  options.jsp.network.wifi = {
    enable = lib.mkEnableOption "NetworkManager with simplified Wi-Fi profiles";

    hostName = lib.mkOption {
      type = lib.types.str;
      default = config.networking.hostName or "nixos";
      description = "Hostname for the machine";
    };

    nameservers = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      description = "List of DNS nameservers";
    };

    envFile = lib.mkOption {
      type = lib.types.nullOr lib.types.path;
      default = null;
      description = "Environment file with PSK variables";
    };

    profiles = lib.mkOption {
      type = lib.types.attrsOf (
        lib.types.submodule (
          { name, ... }:
          {
            options = {
              pskVar = lib.mkOption {
                type = lib.types.nullOr lib.types.str;
                default = null;
                description = "Variable name in envFile providing PSK";
              };
              psk = lib.mkOption {
                type = lib.types.nullOr lib.types.str;
                default = null;
                description = "WiFi password (plaintext - prefer pskVar or pskFile)";
              };
              pskFile = lib.mkOption {
                type = lib.types.nullOr lib.types.path;
                default = null;
                description = "File containing the PSK";
              };
              eduroam = lib.mkOption {
                type = lib.types.bool;
                default = false;
                description = "Enable eduroam configuration";
              };
              identity = lib.mkOption {
                type = lib.types.nullOr lib.types.str;
                default = null;
                description = "Identity for eduroam authentication";
              };
            };
          }
        )
      );
      default = { };
      description = "Map of SSID -> WiFi configuration";
    };
  };

  config = lib.mkIf cfg.enable {
    networking = {
      hostName = lib.mkIf (cfg.hostName != "") cfg.hostName;
      nameservers = lib.mkIf (cfg.nameservers != [ ]) cfg.nameservers;
      useDHCP = false;
      dhcpcd.enable = false;
      networkmanager = {
        enable = true;
        dns = "none";
        ensureProfiles = {
          environmentFiles = lib.optional (cfg.envFile != null) cfg.envFile;
          profiles = lib.mapAttrs mkProfile cfg.profiles;
        };
      };
    };
  };
}
