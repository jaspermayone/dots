{
  lib,
  config,
  pkgs,
  isDarwin,
  ...
}:
with lib;
{
  options.jsp.git = {
    enable = mkEnableOption "Git configuration";
  };

  config = mkIf config.jsp.git.enable {
    programs.git = {
      enable = true;
      lfs.enable = true;

      # Conditional includes for different work contexts
      includes = [
        {
          path = pkgs.writeText "gitconfig-phishdir" ''
            [user]
              email = jasper.mayone@phish.directory
          '';
          condition = "gitdir/i:~/dev/projects/phishdirectory/**";
        }
        {
          path = pkgs.writeText "gitconfig-singlefeather" ''
            [user]
              email = jasper.mayone@singlefeather.com
          '';
          condition = "gitdir/i:~/dev/work/singlefeather/**";
        }
        {
          path = pkgs.writeText "gitconfig-mlh" ''
            [user]
              email = jasper.mayone@majorleaguehacking.com
          '';
          condition = "gitdir/i:~/dev/work/mlh/eng/**";
        }
        {
          path = pkgs.writeText "gitconfig-patchwork" ''
            [user]
              email = jasper@patchworklabs.org
          '';
          condition = "gitdir/i:~/dev/patchwork/**";
        }
        {
          path = pkgs.writeText "gitconfig-school" ''
            [user]
              email = mayonej@wit.edu
          '';
          condition = "gitdir/i:~/dev/school/**";
        }
        {
          path = pkgs.writeText "gitconfig-personal" ''
            [user]
              email = me@jaspermayone.com
          '';
          condition = "gitdir/i:~/dev/personal/**";
        }
      ];

      # Global git ignore
      ignores = [
        # Compiled source
        "*.com"
        "*.class"
        "*.dll"
        "*.exe"
        "*.o"
        "*.so"

        # Packages
        "*.7z"
        "*.dmg"
        "*.gz"
        "*.iso"
        "*.jar"
        "*.rar"
        "*.tar"
        "*.zip"

        # Logs
        "*.log"

        # OS generated files
        ".DS_Store"
        ".DS_Store?"
        "*/.DS_Store"
        "**/.DS_Store"
        "._*"
        ".Spotlight-V100"
        ".Trashes"
        "ehthumbs.db"
        "Thumbs.db"

        # Claude Code
        ".llm-orc/*"
        "CLAUDE.local.md"
      ];

      settings = {
        alias = {
          # Quick shortcuts
          co = "checkout";
          br = "branch";
          ci = "commit";
          st = "status";
          unstage = "reset HEAD --";
          last = "log -1 HEAD";
          pushfwl = "push --force-with-lease --force-if-includes";

          # View abbreviated SHA, description, and history graph of the latest 20 commits
          l = "log --pretty=oneline -n 20 --graph --abbrev-commit";
          lg = "log --oneline --graph --decorate";

          # View the current working tree status using the short format
          s = "status -s";

          # Show the diff between the latest commit and the current state
          d = "!git diff-index --quiet HEAD -- || clear; git --no-pager diff --patch-with-stat";

          # `git di $number` shows the diff between the state `$number` revisions ago and the current state
          di = "!d() { git diff --patch-with-stat HEAD~$1; }; git diff-index --quiet HEAD -- || clear; d";

          # Pull in remote changes for the current repository and all its submodules
          p = "pull --recurse-submodules";

          # Clone a repository including all submodules
          c = "clone --recursive";

          # Commit all changes
          ca = "!git add ':(exclude,attr:builtin_objectmode=160000)' && git commit -av";

          # Switch to a branch, creating it if necessary
          go = "!f() { git checkout -b \"$1\" 2> /dev/null || git checkout \"$1\"; }; f";

          # Show verbose output about tags, branches or remotes
          tags = "tag -l";
          branches = "branch --all";
          remotes = "remote --verbose";

          # List aliases
          aliases = "config --get-regexp alias";

          # Amend the currently staged files to the latest commit
          amend = "commit --amend --reuse-message=HEAD";

          # Credit an author on the latest commit
          credit = "!f() { git commit --amend --author \"$1 <$2>\" -C HEAD; }; f";

          # Interactive rebase with the given number of latest commits
          reb = "!r() { git rebase -i HEAD~$1; }; r";

          # Remove the old tag with this name and tag the latest commit with it
          retag = "!r() { git tag -d $1 && git push origin :refs/tags/$1 && git tag $1; }; r";

          # Find branches containing commit
          fb = "!f() { git branch -a --contains $1; }; f";

          # Find tags containing commit
          ft = "!f() { git describe --always --contains $1; }; f";

          # Find commits by source code
          fc = "!f() { git log --pretty=format:'%C(yellow)%h  %Cblue%ad  %Creset%s%Cgreen  [%cn] %Cred%d' --decorate --date=short -S$1; }; f";

          # Find commits by commit message
          fm = "!f() { git log --pretty=format:'%C(yellow)%h  %Cblue%ad  %Creset%s%Cgreen  [%cn] %Cred%d' --decorate --date=short --grep=$1; }; f";

          # Remove branches that have already been merged with main (a.k.a. 'delete merged')
          dm = "!git branch --merged | grep -v '\\\\*' | xargs -n 1 git branch -d";

          # List contributors with number of commits
          contributors = "shortlog --summary --numbered";

          # Show the user email for the current repository
          whoami = "config user.email";
        };

        user = {
          name = "Jasper Mayone";
          email = "me@jaspermayone.com";
          signingKey = "14D0D45A1DADAAFA";
        };

        init.defaultBranch = "main";

        apply.whitespace = "fix";

        core = {
          editor = "code --wait";
          pager = "less";
          # Treat spaces before tabs and trailing whitespace as errors
          whitespace = "space-before-tab,-indent-with-non-tab,trailing-space";
          # Make `git rebase` safer on macOS
          trustctime = false;
          # Prevent showing files with non-ASCII names as unversioned
          precomposeunicode = false;
          # Speed up commands involving untracked files
          untrackedCache = true;
        };

        color = {
          ui = "auto";
          branch = {
            current = "yellow reverse";
            local = "yellow";
            remote = "green";
          };
        };

        diff = {
          algorithm = "histogram";
          tool = "windsurf";
          renames = "copies"; # Detect copies as well as renames
        };

        "difftool \"windsurf\"".cmd = "windsurf --diff $LOCAL $REMOTE";

        # Binary file diff using hexdump
        "diff \"bin\"".textconv = "hexdump -v -C";

        # Bun lockfile diff
        "diff \"lockb\"" = {
          textconv = "bun";
          binary = true;
        };

        # Include summaries of merged commits in merge commit messages
        merge.log = true;

        pull.rebase = true;

        push = {
          default = "simple";
          followTags = true;
          autoSetupRemote = true;
        };

        rebase.autoStash = true;

        status = {
          submoduleSummary = true;
          showUntrackedFiles = "all";
        };

        tag = {
          sort = "version:refname";
          forceSignAnnotated = true;
          gpgsign = true;
        };

        versionsort = {
          prereleaseSuffix = [
            "-pre"
            ".pre"
            "-beta"
            ".beta"
            "-rc"
            ".rc"
          ];
        };

        commit.gpgSign = true;

        gpg = {
          program = if isDarwin then "/opt/homebrew/bin/gpg" else "gpg";
          format = "openpgp";
        };

        help.autocorrect = 1;

        # URL shorthands
        "url \"git@github.com:\"" = {
          insteadOf = "gh:";
          pushInsteadOf = "https://github.com/";
        };
        "url \"git://github.com/\"".insteadOf = "github:";
        "url \"git@gist.github.com:\"".insteadOf = "gst:";
        "url \"git://gist.github.com/\"".insteadOf = "gist:";

        sequence.editor = "code --wait";

        branch.sort = "-committerdate";
        column.ui = "auto";
      }
      // (
        if isDarwin then
          {
            # macOS specific
            credential = {
              helper = "osxkeychain";
            };
            "credential \"https://dev.azure.com\"".useHttpPath = true;
          }
        else
          { }
      );
    };

    # Delta for better diffs
    programs.delta = {
      enable = true;
      options = {
        navigate = true;
        light = false;
        line-numbers = true;
      };
    };

    # GitHub CLI
    programs.gh = {
      enable = true;
      settings = {
        git_protocol = "ssh";
      };
    };

    # Lazygit
    programs.lazygit = {
      enable = true;
      settings = {
        gui.theme = {
          lightTheme = false;
          activeBorderColor = [
            "blue"
            "bold"
          ];
          inactiveBorderColor = [ "black" ];
          selectedLineBgColor = [ "default" ];
        };
      };
    };

    # GitHub Dashboard
    programs.gh-dash = {
      enable = true;
      settings = {
        prSections = [
          {
            title = "Mine";
            filters = "is:open author:@me updated:>={{ nowModify \"-3w\" }} sort:updated-desc archived:false";
            layout.author.hidden = true;
          }
          {
            title = "Review";
            filters = "sort:updated-desc is:pr is:open review-requested:jaspermayone archived:false";
          }
          {
            title = "All";
            filters = "sort:updated-desc is:pr is:open user:@me archived:false";
          }
        ];
        issuesSections = [
          {
            title = "Assigned";
            filters = "is:issue state:open archived:false assignee:@me sort:updated-desc";
          }
          {
            title = "Created";
            filters = "author:@me is:open archived:false";
          }
          {
            title = "All";
            filters = "is:issue involves:@me archived:false sort:updated-desc is:open";
          }
        ];
        defaults = {
          view = "prs";
          refetchIntervalMinutes = 5;
          layout.prs = {
            repoName = {
              grow = true;
              width = 10;
              hidden = false;
            };
            base.hidden = true;
          };
          preview = {
            open = true;
            width = 84;
          };
          prsLimit = 20;
          issuesLimit = 20;
        };
        repoPaths = {
          "jaspermayone/*" = "~/dev/personal/*";
          "phishdirectory/*" = "~/dev/projects/phishdirectory/*";
        };
        keybindings = {
          universal = [
            {
              key = "g";
              name = "lazygit";
              command = "cd {{.RepoPath}} && lazygit";
            }
          ];
          prs = [
            {
              key = "O";
              builtin = "checkout";
            }
            {
              key = "m";
              command = "gh pr merge --admin --repo {{.RepoName}} {{.PrNumber}}";
            }
            {
              key = "a";
              name = "lazygit add";
              command = "cd {{.RepoPath}} && git add -A && lazygit";
            }
            {
              key = "v";
              name = "approve";
              command = "gh pr review --repo {{.RepoName}} --approve --body \"$(gum input --prompt='Approval Comment: ')\" {{.PrNumber}}";
            }
          ];
        };
        theme = {
          ui = {
            sectionsShowCount = true;
            table.compact = false;
          };
        };
      };
    };
  };
}
