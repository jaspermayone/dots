#compdef castle
# Zsh completion for castle CLI
# Credit: Based on implementation by krn (https://github.com/taciturnaxolotl/dots)

_castle() {
    local -a commands backup_commands

    commands=(
        'backup:Manage backups and restores'
        '--help:Show help message'
    )

    backup_commands=(
        'status:Show backup status for all services'
        'list:List snapshots'
        'run:Trigger manual backup'
        'restore:Interactive restore wizard'
        'dr:Disaster recovery mode'
    )

    case "${words[2]}" in
        backup)
            _describe -t backup_commands 'backup command' backup_commands
            ;;
        *)
            _describe -t commands 'castle command' commands
            ;;
    esac
}

_castle "$@"
