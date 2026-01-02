# castle CLI - Hogwarts infrastructure management
# Credit: Based on implementation by krn (https://github.com/taciturnaxolotl/dots)
#
# Commands:
#   sudo castle                    - Interactive menu
#   sudo castle backup             - Backup management submenu
#   sudo castle backup status      - Show backup status for all services
#   sudo castle backup list        - List snapshots
#   sudo castle backup run         - Trigger manual backup
#   sudo castle backup restore     - Interactive restore wizard
#   sudo castle backup dr          - Disaster recovery mode
#
# Future modules:
#   castle status     - Service health dashboard
#   castle secrets    - Manage agenix secrets
#   castle deploy     - Remote deployment tools
#   castle logs       - Service log viewer

{ config, lib, pkgs, ... }:

let
  cfg = config.castle.backup;

  # Get all configured backup services
  allBackupServices = lib.attrNames cfg.services;

  # Generate manifest for disaster recovery
  backupManifest = pkgs.writeText "backup-manifest.json" (builtins.toJSON {
    version = 1;
    generated = "nixos-rebuild";
    services = lib.mapAttrs (name: backupCfg: {
      paths = backupCfg.paths;
      exclude = backupCfg.exclude or [];
      tags = backupCfg.tags or [];
    }) cfg.services;
  });

  castleCliScript = pkgs.writeShellScript "castle" ''
    set -e

    # Must be run as root
    if [ "$(id -u)" -ne 0 ]; then
      echo "Error: castle must be run as root (use sudo)"
      exit 1
    fi

    # Colors via gum
    style() { ${pkgs.gum}/bin/gum style "$@"; }
    confirm() { ${pkgs.gum}/bin/gum confirm "$@"; }
    choose() { ${pkgs.gum}/bin/gum choose "$@"; }
    input() { ${pkgs.gum}/bin/gum input "$@"; }
    spin() { ${pkgs.gum}/bin/gum spin "$@"; }

    # Load B2 credentials for backup commands
    load_backup_env() {
      set -a
      source ${config.age.secrets."restic/env".path}
      set +a
    }

    # Restic wrapper with secrets
    restic_cmd() {
      ${pkgs.restic}/bin/restic \
        --repository-file ${config.age.secrets."restic/repo".path} \
        --password-file ${config.age.secrets."restic/password".path} \
        "$@"
    }

    # Available backup services
    BACKUP_SERVICES="${lib.concatStringsSep " " allBackupServices}"
    MANIFEST="${backupManifest}"

    # ========== BACKUP COMMANDS ==========

    backup_status() {
      load_backup_env
      style --bold --foreground 212 "Backup Status"
      echo

      for svc in $BACKUP_SERVICES; do
        latest=$(restic_cmd snapshots --tag "service:$svc" --json --latest 1 2>/dev/null | ${pkgs.jq}/bin/jq -r '.[0] // empty')

        if [ -n "$latest" ]; then
          time=$(echo "$latest" | ${pkgs.jq}/bin/jq -r '.time' | cut -d'T' -f1)
          hostname=$(echo "$latest" | ${pkgs.jq}/bin/jq -r '.hostname')
          style --foreground 35 "✓ $svc"
          style --foreground 117 "    Last backup: $time on $hostname"
        else
          style --foreground 214 "! $svc"
          style --foreground 117 "    No backups found"
        fi
      done
    }

    backup_list() {
      load_backup_env
      style --bold --foreground 212 "List Snapshots"
      echo

      svc=$(echo "$BACKUP_SERVICES" | tr ' ' '\n' | choose --header "Select service:")

      if [ -z "$svc" ]; then
        style --foreground 196 "No service selected"
        exit 1
      fi

      style --foreground 117 "Snapshots for $svc:"
      echo

      restic_cmd snapshots --tag "service:$svc" --compact
    }

    backup_run() {
      style --bold --foreground 212 "Manual Backup"
      echo

      svc=$(echo "all $BACKUP_SERVICES" | tr ' ' '\n' | choose --header "Select service to backup:")

      if [ -z "$svc" ]; then
        style --foreground 196 "No service selected"
        exit 1
      fi

      if [ "$svc" = "all" ]; then
        for s in $BACKUP_SERVICES; do
          style --foreground 117 "Backing up $s..."
          systemctl start "restic-backups-$s.service" || style --foreground 214 "! Failed to backup $s"
        done
      else
        style --foreground 117 "Backing up $svc..."
        systemctl start "restic-backups-$svc.service"
      fi

      style --foreground 35 "✓ Backup triggered"
    }

    backup_restore() {
      load_backup_env
      style --bold --foreground 212 "Restore Wizard"
      echo

      svc=$(echo "$BACKUP_SERVICES" | tr ' ' '\n' | choose --header "Select service to restore:")

      if [ -z "$svc" ]; then
        style --foreground 196 "No service selected"
        exit 1
      fi

      style --foreground 117 "Fetching snapshots for $svc..."
      snapshots=$(restic_cmd snapshots --tag "service:$svc" --json 2>/dev/null)

      if [ "$(echo "$snapshots" | ${pkgs.jq}/bin/jq 'length')" = "0" ]; then
        style --foreground 196 "No snapshots found for $svc"
        exit 1
      fi

      snapshot_list=$(echo "$snapshots" | ${pkgs.jq}/bin/jq -r '.[] | "\(.short_id) - \(.time | split("T")[0]) - \(.paths | join(", "))"')

      selected=$(echo "$snapshot_list" | choose --header "Select snapshot:")
      snapshot_id=$(echo "$selected" | cut -d' ' -f1)

      if [ -z "$snapshot_id" ]; then
        style --foreground 196 "No snapshot selected"
        exit 1
      fi

      restore_mode=$(choose --header "Restore mode:" "Inspect (restore to /tmp)" "In-place (DANGEROUS)")

      case "$restore_mode" in
        "Inspect"*)
          target="/tmp/restore-$svc-$snapshot_id"
          mkdir -p "$target"

          style --foreground 117 "Restoring to $target..."
          restic_cmd restore "$snapshot_id" --target "$target"

          style --foreground 35 "✓ Restored to $target"
          style --foreground 117 "  Inspect files, then copy what you need"
          ;;

        "In-place"*)
          style --foreground 196 --bold "⚠ WARNING: This will overwrite existing data!"
          echo

          if ! confirm "Stop $svc and restore data?"; then
            style --foreground 214 "Restore cancelled"
            exit 0
          fi

          style --foreground 117 "Stopping $svc..."
          systemctl stop "$svc" 2>/dev/null || true

          style --foreground 117 "Restoring snapshot $snapshot_id..."
          restic_cmd restore "$snapshot_id" --target /

          style --foreground 117 "Starting $svc..."
          systemctl start "$svc"

          style --foreground 35 "✓ Restore complete"
          ;;
      esac
    }

    backup_dr() {
      load_backup_env
      style --bold --foreground 196 "⚠ DISASTER RECOVERY MODE"
      echo
      style --foreground 214 "This will restore ALL services from backup."
      style --foreground 214 "Only use this on a fresh NixOS install."
      echo

      if ! confirm "Continue with full disaster recovery?"; then
        style --foreground 117 "Cancelled"
        exit 0
      fi

      style --foreground 117 "Reading backup manifest..."

      for svc in $BACKUP_SERVICES; do
        style --foreground 212 "Restoring $svc..."

        snapshot_id=$(restic_cmd snapshots --tag "service:$svc" --json --latest 1 2>/dev/null | ${pkgs.jq}/bin/jq -r '.[0].short_id // empty')

        if [ -z "$snapshot_id" ]; then
          style --foreground 214 "  ! No snapshots found, skipping"
          continue
        fi

        systemctl stop "$svc" 2>/dev/null || true
        restic_cmd restore "$snapshot_id" --target /
        systemctl start "$svc" 2>/dev/null || true

        style --foreground 35 "  ✓ Restored from $snapshot_id"
      done

      echo
      style --foreground 35 --bold "✓ Disaster recovery complete"
    }

    backup_menu() {
      style --bold --foreground 212 "Backup Management"
      echo

      action=$(choose \
        "Status - Show backup status" \
        "List - Browse snapshots" \
        "Run - Trigger manual backup" \
        "Restore - Restore from backup" \
        "DR - Disaster recovery mode" \
        "← Back")

      case "$action" in
        Status*) backup_status ;;
        List*) backup_list ;;
        Run*) backup_run ;;
        Restore*) backup_restore ;;
        DR*) backup_dr ;;
        *) main_menu ;;
      esac
    }

    # ========== MAIN MENU ==========

    main_menu() {
      style --bold --foreground 212 "🏰 Castle - Hogwarts Infrastructure"
      echo

      action=$(choose \
        "Backup - Manage backups and restores" \
        "Exit")

      case "$action" in
        Backup*) backup_menu ;;
        *) exit 0 ;;
      esac
    }

    show_help() {
      echo "Usage: castle [command] [subcommand]"
      echo
      echo "Commands:"
      echo "  backup              Backup management menu"
      echo "  backup status       Show backup status for all services"
      echo "  backup list         List snapshots"
      echo "  backup run          Trigger manual backup"
      echo "  backup restore      Interactive restore wizard"
      echo "  backup dr           Disaster recovery mode"
      echo
      echo "Run without arguments for interactive menu."
      echo
      echo "Note: Must be run as root (use sudo)"
    }

    # ========== MAIN ==========

    case "''${1:-}" in
      backup)
        case "''${2:-}" in
          status) backup_status ;;
          list) backup_list ;;
          run) backup_run ;;
          restore) backup_restore ;;
          dr|disaster-recovery) backup_dr ;;
          "") backup_menu ;;
          *)
            style --foreground 196 "Unknown backup command: $2"
            exit 1
            ;;
        esac
        ;;
      --help|-h)
        show_help
        ;;
      "")
        main_menu
        ;;
      *)
        style --foreground 196 "Unknown command: $1"
        echo "Run 'castle --help' for usage."
        exit 1
        ;;
    esac
  '';

  castleCli = pkgs.stdenv.mkDerivation {
    pname = "castle";
    version = "1.0.0";

    dontUnpack = true;

    nativeBuildInputs = [ pkgs.installShellFiles ];

    bashCompletionSrc = ./completions/castle.bash;
    zshCompletionSrc = ./completions/castle.zsh;
    fishCompletionSrc = ./completions/castle.fish;

    installPhase = ''
      mkdir -p $out/bin
      cp ${castleCliScript} $out/bin/castle
      chmod +x $out/bin/castle

      # Install completions
      installShellCompletion --bash --name castle $bashCompletionSrc
      installShellCompletion --zsh --name _castle $zshCompletionSrc
      installShellCompletion --fish --name castle.fish $fishCompletionSrc
    '';

    meta = with lib; {
      description = "Hogwarts castle infrastructure management CLI";
      license = licenses.mit;
    };
  };

in {
  config = lib.mkIf cfg.enable {
    environment.systemPackages = [ castleCli pkgs.gum pkgs.jq ];

    # Store manifest for reference
    environment.etc."castle/backup-manifest.json".source = backupManifest;
  };
}
