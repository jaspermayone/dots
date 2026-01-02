# Bash completion for castle CLI
# Credit: Based on implementation by krn (https://github.com/taciturnaxolotl/dots)

_castle() {
    local cur prev words cword
    _init_completion || return

    local commands="backup"
    local backup_commands="status list run restore dr"

    case "${prev}" in
        castle)
            COMPREPLY=($(compgen -W "${commands} --help" -- "${cur}"))
            return
            ;;
        backup)
            COMPREPLY=($(compgen -W "${backup_commands}" -- "${cur}"))
            return
            ;;
    esac

    COMPREPLY=()
}

complete -F _castle castle
