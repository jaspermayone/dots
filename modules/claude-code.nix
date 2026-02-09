# Claude Code configuration module
{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.jsp.claude-code;

  # Guardrails hook script
  guardrailScript = pkgs.writeText "guardrail.py" ''
    #!/usr/bin/env python3
    """
    PreToolUse hook for Claude Code that enforces local guardrails.

    Receives tool call details on stdin, applies policy rules, and outputs
    a JSON response indicating whether to allow or deny the call.

    Environment variables:
    - GUARDRAILS_POLICY_PATH: Path to policy.yaml (default: ./policy.yaml)
    - GUARDRAILS_VERBOSE: Set to 1 to log decisions to stderr
    """

    import json
    import sys
    import os
    from pathlib import Path
    from typing import Dict, Any, List
    import yaml


    def log(message: str):
        """Log to stderr if verbose mode is enabled."""
        if os.environ.get("GUARDRAILS_VERBOSE") == "1":
            print(f"[guardrails] {message}", file=sys.stderr)


    def load_policy() -> Dict[str, Any]:
        """Load policy configuration from policy.yaml."""
        # Check for custom policy path
        policy_path_env = os.environ.get("GUARDRAILS_POLICY_PATH")
        if policy_path_env:
            policy_path = Path(policy_path_env)
        else:
            # Default to policy.yaml in the same directory as this script
            script_dir = Path(__file__).parent
            policy_path = script_dir / "policy.yaml"

        if not policy_path.exists():
            log(f"Policy file not found at {policy_path}, using defaults")
            # Return default policy if file doesn't exist
            return {
                "secret_patterns": ["*.env", ".env", ".env.*", "secrets.*", "*.age"],
                "dotfiles_root": "/Users/jsp/dev/dots",
                "dotfiles_allowlist": [],
                "dangerous_patterns": ["rm -rf /", "rm -rf ~"],
                "safe_patterns": ["rm -rf node_modules", "rm -rf dist", "rm -rf build"],
                "blocked_git_commands": ["commit", "push", "rebase", "merge"],
                "blocked_env_commands": ["printenv", "env"]
            }

        log(f"Loading policy from {policy_path}")
        with open(policy_path, 'r') as f:
            return yaml.safe_load(f)


    def matches_pattern(path: str, patterns: List[str]) -> bool:
        """Check if path matches any glob pattern."""
        from fnmatch import fnmatch

        path_obj = Path(path)
        for pattern in patterns:
            # Check both full path and basename
            if fnmatch(str(path_obj), pattern) or fnmatch(path_obj.name, pattern):
                return True
            # Also check parent directories for patterns like **/secrets/**
            for parent in path_obj.parents:
                if fnmatch(str(parent), pattern):
                    return True
        return False


    def is_secret_file(path: str, policy: Dict[str, Any]) -> bool:
        """Check if path is a secret file."""
        secret_patterns = policy.get("secret_patterns", [])
        return matches_pattern(path, secret_patterns)


    def is_dotfiles_path(path: str, policy: Dict[str, Any]) -> bool:
        """Check if path is under dotfiles root and not allowlisted."""
        dotfiles_root = policy.get("dotfiles_root", "")
        if not dotfiles_root:
            return False

        path_obj = Path(path).resolve()
        dotfiles_obj = Path(dotfiles_root).resolve()

        # Always allow access to .claude directory (even if under dotfiles)
        claude_dir = Path.home() / ".claude"
        try:
            path_obj.relative_to(claude_dir)
            return False  # Under .claude, always allow
        except ValueError:
            pass  # Not under .claude, continue checking

        # Check if path is under dotfiles root
        try:
            path_obj.relative_to(dotfiles_obj)
            is_under_dotfiles = True
        except ValueError:
            is_under_dotfiles = False

        if not is_under_dotfiles:
            return False

        # Check if it's in the allowlist
        allowlist = policy.get("dotfiles_allowlist", [])
        for allowed_path in allowlist:
            allowed_obj = Path(allowed_path).resolve()
            try:
                path_obj.relative_to(allowed_obj)
                return False  # Allowlisted
            except ValueError:
                continue

        return True  # Under dotfiles but not allowlisted


    def is_dangerous_bash(command: str, policy: Dict[str, Any]) -> bool:
        """Check if bash command is dangerous."""
        dangerous_patterns = policy.get("dangerous_patterns", [])
        safe_patterns = policy.get("safe_patterns", [])

        # First check if it matches a safe pattern
        for safe_pattern in safe_patterns:
            if safe_pattern in command:
                return False

        # Then check if it matches a dangerous pattern
        for dangerous_pattern in dangerous_patterns:
            if dangerous_pattern in command:
                return True

        return False


    def is_blocked_git_command(command: str, policy: Dict[str, Any]) -> bool:
        """Check if git command modifies history or remotes."""
        blocked_commands = policy.get("blocked_git_commands", [])

        # Parse git command
        if not command.strip().startswith("git "):
            return False

        # Extract the git subcommand
        parts = command.strip().split()
        if len(parts) < 2:
            return False

        git_subcommand = parts[1]

        # Check against blocked list
        for blocked in blocked_commands:
            if git_subcommand == blocked or command.find(f"git {blocked}") != -1:
                return True

        return False


    def is_blocked_env_command(command: str, policy: Dict[str, Any]) -> bool:
        """Check if command dumps environment variables."""
        blocked_commands = policy.get("blocked_env_commands", [])

        command_stripped = command.strip()
        for blocked in blocked_commands:
            if command_stripped == blocked or command_stripped.startswith(f"{blocked} "):
                return True

        return False


    def check_tool_call(tool_name: str, tool_args: Dict[str, Any], policy: Dict[str, Any]) -> Dict[str, Any]:
        """
        Evaluate a tool call against policy rules.

        Returns a dict with:
        - action: "allow" or "deny"
        - reason: explanation if denied
        """

        # Check Read tool
        if tool_name == "Read":
            file_path = tool_args.get("file_path", "")

            if is_secret_file(file_path, policy):
                log(f"DENY: Read secret file {file_path}")
                return {
                    "action": "deny",
                    "reason": f"Blocked reading secret file: {file_path}. Override explicitly if needed."
                }

            if is_dotfiles_path(file_path, policy):
                log(f"DENY: Read dotfiles {file_path}")
                return {
                    "action": "deny",
                    "reason": f"Blocked reading dotfiles: {file_path}. Add to allowlist if working on this module."
                }

        # Check Edit/Write tools
        elif tool_name in ["Edit", "Write"]:
            file_path = tool_args.get("file_path", "")

            if is_secret_file(file_path, policy):
                log(f"DENY: Write secret file {file_path}")
                return {
                    "action": "deny",
                    "reason": f"Blocked writing to secret file: {file_path}. Override explicitly if needed."
                }

            if is_dotfiles_path(file_path, policy):
                log(f"DENY: Write dotfiles {file_path}")
                return {
                    "action": "deny",
                    "reason": f"Blocked writing to dotfiles: {file_path}. Add to allowlist if working on this module."
                }

        # Check Bash tool
        elif tool_name == "Bash":
            command = tool_args.get("command", "")

            if is_blocked_env_command(command, policy):
                log(f"DENY: Env dump command {command}")
                return {
                    "action": "deny",
                    "reason": f"Blocked environment dump command: {command}. Ask explicitly if you need env vars."
                }

            if is_blocked_git_command(command, policy):
                log(f"DENY: Git command {command}")
                return {
                    "action": "deny",
                    "reason": f"Blocked git command that modifies history/remotes: {command}. Git is read-only by default."
                }

            if is_dangerous_bash(command, policy):
                log(f"DENY: Dangerous command {command}")
                return {
                    "action": "deny",
                    "reason": f"Blocked potentially dangerous command: {command}"
                }

        # Allow by default
        log(f"ALLOW: {tool_name}")
        return {"action": "allow"}


    def main():
        """Main entry point for PreToolUse hook."""
        try:
            # Read tool call details from stdin
            input_data = json.load(sys.stdin)

            tool_name = input_data.get("tool", "")
            tool_args = input_data.get("arguments", {})

            log(f"Checking tool call: {tool_name}")

            # Load policy
            policy = load_policy()

            # Check the tool call
            result = check_tool_call(tool_name, tool_args, policy)

            # Output result
            json.dump(result, sys.stdout)
            sys.exit(0)

        except Exception as e:
            # On error, allow the call but log the error
            log(f"ERROR: {str(e)}")
            json.dump({
                "action": "allow",
                "reason": f"Guardrail error (allowing by default): {str(e)}"
            }, sys.stdout)
            sys.exit(0)


    if __name__ == "__main__":
        main()
  '';

  # Policy configuration
  policyConfig = pkgs.writeText "policy.yaml" ''
    # Secret file patterns to block
    secret_patterns:
      - "*.env"
      - ".env"
      - ".env.*"
      - "secrets.*"
      - "*.age"
      - "**/secrets/**"
      - "**/.env"
      - "**/.env.*"
      - "**/secrets.*"
      - "**/*.age"

    # Dotfiles root (protected by default)
    dotfiles_root: "/Users/jsp/dev/dots"

    # Allowed subpaths under dotfiles (when explicitly working on them)
    # NOTE: .claude directory is automatically excluded even if under dotfiles
    dotfiles_allowlist: []

    # Dangerous shell command patterns to block
    dangerous_patterns:
      - "rm -rf /"
      - "rm -rf ~"
      - "rm -rf $HOME"
      - "sudo rm -rf /"
      - "> /dev/sda"
      - "dd if=/dev/zero"
      - "mkfs"
      - "chmod -R 777 /"
      - "chown -R"

    # Safe patterns that override dangerous patterns
    safe_patterns:
      - "rm -rf node_modules"
      - "rm -rf dist"
      - "rm -rf build"
      - "rm -rf .next"
      - "rm -rf coverage"
      - "rm -rf target"
      - "rm -rf out"
      - "rm -rf .cache"
      - "rm -rf tmp"
      - "rm -rf temp"

    # Git commands that modify history/remotes (read-only is OK)
    blocked_git_commands:
      - "commit"
      - "push"
      - "rebase"
      - "merge"
      - "cherry-pick"
      - "reset --hard"
      - "clean -f"
      - "push --force"
      - "force-push"

    # Blocked environment variable commands
    blocked_env_commands:
      - "printenv"
      - "env"
      - "export -p"
  '';

  # Wrapper script to make it executable
  guardrailExecutable = pkgs.writeShellScriptBin "guardrail" ''
    exec ${pkgs.python3.withPackages (ps: [ ps.pyyaml ])}/bin/python3 ${guardrailScript} "$@"
  '';

in
{
  options.jsp.claude-code = {
    enable = lib.mkEnableOption "Claude Code configuration";

    guardrails = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Enable guardrails PreToolUse hook";
      };

      verbose = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = "Enable verbose logging for guardrails";
      };
    };

    settings = lib.mkOption {
      type = lib.types.attrs;
      default = { };
      description = "Additional Claude Code settings";
    };
  };

  config = lib.mkIf cfg.enable {
    # Install guardrail script and policy to ~/.claude/hooks/
    home.file = {
      ".claude/hooks/guardrail.py" = lib.mkIf cfg.guardrails.enable {
        source = "${guardrailExecutable}/bin/guardrail";
        executable = true;
      };

      ".claude/hooks/policy.yaml" = lib.mkIf cfg.guardrails.enable {
        source = policyConfig;
      };

      # Settings are managed by symlink from /nix/store, so we use programs.claude-code
    };

    # Claude Code settings (will be symlinked from /nix/store)
    programs.claude-code.settings =
      lib.mkMerge [
        # Guardrails configuration
        (lib.mkIf cfg.guardrails.enable {
          hooks = {
            PreToolUse = "${config.home.homeDirectory}/.claude/hooks/guardrail.py";
          };
          env = {
            GUARDRAILS_POLICY_PATH = "${config.home.homeDirectory}/.claude/hooks/policy.yaml";
            GUARDRAILS_VERBOSE = if cfg.guardrails.verbose then "1" else "0";
          };
        })

        # Additional user settings
        cfg.settings
      ];
  };
}
