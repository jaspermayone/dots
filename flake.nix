{
  description = "@jaspermayone's NixOS and nix-darwin config";

  inputs = {
    # Nixpkgs
    nixpkgs.url = "github:nixos/nixpkgs/nixos-25.11";
    nixpkgs-unstable.url = "github:nixos/nixpkgs/nixos-unstable";

    # NixOS hardware configuration
    hardware.url = "github:NixOS/nixos-hardware/master";

    # Home manager
    home-manager.url = "github:nix-community/home-manager/release-25.11";
    home-manager.inputs.nixpkgs.follows = "nixpkgs";

    # Nix-Darwin
    nix-darwin.url = "github:nix-darwin/nix-darwin/nix-darwin-25.11";
    nix-darwin.inputs.nixpkgs.follows = "nixpkgs";

    agenix.url = "github:ryantm/agenix";

    claude-desktop = {
      url = "github:k3d3/claude-desktop-linux-flake";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    import-tree.url = "github:vic/import-tree";

    nur = {
      url = "github:nix-community/NUR";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    deploy-rs = {
      url = "github:serokell/deploy-rs";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    tangled = {
      url = "git+https://tangled.org/tangled.org/core";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    zmx = {
      url = "github:neurosnap/zmx";
    };

    rust-fp = {
      url = "github:ChocolateLoverRaj/rust-fp";
    };

    tgirlpkgs = {
      url = "github:tgirlcloud/pkgs";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    strings = {
      url = "github:jaspermayone/strings";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    try = {
      url = "github:tobi/try";
    };
  };

  outputs =
    {
      self,
      nixpkgs,
      nixpkgs-unstable,
      agenix,
      home-manager,
      nur,
      nix-darwin,
      deploy-rs,
      tangled,
      tgirlpkgs,
      rust-fp,
      strings,
      try,
      ...
    }@inputs:
    let
      outputs = inputs.self.outputs;

      # Overlay to make unstable packages available as pkgs.unstable.*
      # Also includes custom packages
      unstable-overlays = {
        nixpkgs.overlays = [
          (final: prev: {
            unstable = import nixpkgs-unstable {
              system = final.stdenv.hostPlatform.system;
              config.allowUnfree = true;
            };

            # Custom packages
            zmx-binary = prev.callPackage ./packages/zmx.nix { };
            wut = prev.callPackage ./packages/wut.nix { };

            # Caddy with Cloudflare DNS plugin for ACME DNS challenges
            caddy-cloudflare = prev.caddy.withPlugins {
              plugins = [ "github.com/caddy-dns/cloudflare@v0.2.2" ];
              hash = "sha256-dnhEjopeA0UiI+XVYHYpsjcEI6Y1Hacbi28hVKYQURg=";
            };
          })
        ];
      };

      # Helper function to create NixOS configurations
      mkNixos =
        hostname: system:
        nixpkgs.lib.nixosSystem {
          specialArgs = { inherit inputs outputs hostname; };
          modules = [
            { nixpkgs.hostPlatform = system; }
            ./hosts/${hostname}/configuration.nix
            agenix.nixosModules.default
            tgirlpkgs.nixosModules.default
            unstable-overlays
            nur.modules.nixos.default
            home-manager.nixosModules.home-manager
            {
              home-manager.useGlobalPkgs = true;
              home-manager.useUserPackages = true;
              home-manager.backupFileExtension = "backup";
              home-manager.extraSpecialArgs = {
                inherit inputs outputs hostname;
                isDarwin = false;
              };
              home-manager.users.jsp = import ./home;
            }
          ];
        };

      # Helper function to create Darwin configurations
      mkDarwin =
        hostname: system:
        nix-darwin.lib.darwinSystem {
          specialArgs = { inherit inputs outputs hostname; };
          modules = [
            { nixpkgs.hostPlatform = system; }
            ./darwin
            ./hosts/${hostname}
            agenix.darwinModules.default
            unstable-overlays
            nur.modules.darwin.default
            home-manager.darwinModules.home-manager
            {
              home-manager.useGlobalPkgs = true;
              home-manager.useUserPackages = true;
              home-manager.backupFileExtension = "backup";
              home-manager.extraSpecialArgs = {
                inherit inputs outputs hostname;
                isDarwin = true;
              };
              home-manager.users.jsp = import ./home;
            }
          ];
        };
    in
    {
      # NixOS configurations
      # Available through 'nixos-rebuild --flake .#hostname'
      nixosConfigurations = {
        alastor = mkNixos "alastor" "aarch64-linux";
        horace = mkNixos "horace" "x86_64-linux";
      };

      # Darwin configurations
      # Available through 'darwin-rebuild switch --flake .#hostname'
      darwinConfigurations = {
        remus = mkDarwin "remus" "aarch64-darwin";
        dippet = mkDarwin "dippet" "aarch64-darwin";
      };

      # Formatters
      formatter.x86_64-linux = nixpkgs.legacyPackages.x86_64-linux.nixfmt-tree;
      formatter.aarch64-darwin = nixpkgs.legacyPackages.aarch64-darwin.nixfmt-tree;

      # Deploy-rs configurations
      # Available through 'deploy .#alastor'
      deploy.nodes = {
        alastor = {
          hostname = "alastor";
          profiles.system = {
            sshUser = "jsp";
            user = "root";
            path = deploy-rs.lib.aarch64-linux.activate.nixos self.nixosConfigurations.alastor;
          };
        };
        horace = {
          hostname = "horace";
          profiles.system = {
            sshUser = "jsp";
            user = "root";
            path = deploy-rs.lib.x86_64-linux.activate.nixos self.nixosConfigurations.horace;
          };
        };
      };

      # Validation checks for deploy-rs
      checks = builtins.mapAttrs (system: deployLib: deployLib.deployChecks self.deploy) deploy-rs.lib;
    };
}
