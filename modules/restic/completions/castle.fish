# Fish completion for castle CLI
# Credit: Based on implementation by krn (https://github.com/taciturnaxolotl/dots)

# Disable file completions
complete -c castle -f

# Top-level commands
complete -c castle -n "__fish_use_subcommand" -a "backup" -d "Manage backups and restores"
complete -c castle -n "__fish_use_subcommand" -a "--help" -d "Show help message"

# Backup subcommands
complete -c castle -n "__fish_seen_subcommand_from backup" -a "status" -d "Show backup status for all services"
complete -c castle -n "__fish_seen_subcommand_from backup" -a "list" -d "List snapshots"
complete -c castle -n "__fish_seen_subcommand_from backup" -a "run" -d "Trigger manual backup"
complete -c castle -n "__fish_seen_subcommand_from backup" -a "restore" -d "Interactive restore wizard"
complete -c castle -n "__fish_seen_subcommand_from backup" -a "dr" -d "Disaster recovery mode"
