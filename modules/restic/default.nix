# Restic backup module for NixOS
# Credit: Based on implementation by krn (https://github.com/taciturnaxolotl/dots)
#
# Provides automated backups to Backblaze B2 (or any restic-compatible backend)
# with per-service configuration, database handling, and an interactive CLI.
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.castle.backup;

  # Create a restic backup job for a service
  mkBackupJob = name: serviceCfg: {
    inherit (serviceCfg) paths;
    exclude = serviceCfg.exclude;

    initialize = true;

    # Use secrets from agenix
    environmentFile = config.age.secrets."restic/env".path;
    repositoryFile = config.age.secrets."restic/repo".path;
    passwordFile = config.age.secrets."restic/password".path;

    # Tags for easier filtering during restore
    extraBackupArgs = (map (t: "--tag ${t}") (serviceCfg.tags or [ "service:${name}" ])) ++ [
      "--verbose"
    ];

    # Retention policy
    pruneOpts = [
      "--keep-last 3"
      "--keep-daily 7"
      "--keep-weekly 5"
      "--keep-monthly 12"
      "--tag service:${name}"
    ];

    # Backup schedule (nightly at 2 AM + random delay)
    timerConfig = {
      OnCalendar = "02:00";
      RandomizedDelaySec = "2h";
      Persistent = true;
    };

    # Pre/post backup hooks for database consistency
    backupPrepareCommand = lib.optionalString (
      serviceCfg.preBackup or null != null
    ) serviceCfg.preBackup;
    backupCleanupCommand = lib.optionalString (
      serviceCfg.postBackup or null != null
    ) serviceCfg.postBackup;
  };

in
{
  imports = [ ./cli.nix ];

  options.castle.backup = {
    enable = lib.mkEnableOption "Restic backup system";

    services = lib.mkOption {
      type = lib.types.attrsOf (
        lib.types.submodule {
          options = {
            enable = lib.mkOption {
              type = lib.types.bool;
              default = true;
              description = "Enable backups for this service";
            };

            paths = lib.mkOption {
              type = lib.types.listOf lib.types.str;
              description = "Paths to back up";
            };

            exclude = lib.mkOption {
              type = lib.types.listOf lib.types.str;
              default = [
                "*.log"
                "node_modules"
                ".git"
              ];
              description = "Glob patterns to exclude from backup";
            };

            tags = lib.mkOption {
              type = lib.types.listOf lib.types.str;
              default = [ ];
              description = "Tags to apply to snapshots";
            };

            preBackup = lib.mkOption {
              type = lib.types.nullOr lib.types.str;
              default = null;
              description = "Command to run before backup (e.g., stop service, checkpoint DB)";
            };

            postBackup = lib.mkOption {
              type = lib.types.nullOr lib.types.str;
              default = null;
              description = "Command to run after backup (e.g., restart service)";
            };
          };
        }
      );
      default = { };
      description = "Per-service backup configurations";
    };
  };

  config = lib.mkIf cfg.enable {
    # Ensure secrets are defined
    assertions = [
      {
        assertion = config.age.secrets ? "restic/env";
        message = "castle.backup requires age.secrets.\"restic/env\" to be defined";
      }
      {
        assertion = config.age.secrets ? "restic/repo";
        message = "castle.backup requires age.secrets.\"restic/repo\" to be defined";
      }
      {
        assertion = config.age.secrets ? "restic/password";
        message = "castle.backup requires age.secrets.\"restic/password\" to be defined";
      }
    ];

    # Create restic backup jobs for each enabled service
    services.restic.backups = lib.mapAttrs mkBackupJob (lib.filterAttrs (n: v: v.enable) cfg.services);

    # Add restic and sqlite to system packages for manual operations
    environment.systemPackages = [
      pkgs.restic
      pkgs.sqlite
    ];
  };
}
