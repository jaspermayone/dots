{
  description = "@jaspermayone's probobly broken nix dots";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-25.05-darwin";
    nix-darwin.url = "github:nix-darwin/nix-darwin/nix-darwin-25.05";
    nix-darwin.inputs.nixpkgs.follows = "nixpkgs";

    home-manager = {
      url = "github:nix-community/home-manager/release-25.05";
      inputs.nixpkgs.follows = "nixpkgs";
    };



  };

  outputs = inputs@{ self, nix-darwin, nixpkgs, home-manager }:
  {
     # Machine configurations
    darwinConfigurations = {

      # remus (main macbook)
      "remus" = nix-darwin.lib.darwinSystem {
        modules = [
          ./machines/remus/configuration.nix
          home-manager.darwinModules.home-manager
          {
            home-manager = {
              useGlobalPkgs = true;
              useUserPackages = true;
              users.jsp = import ./machines/remus/home.nix;
            };
          }
        ];
      };

      # Add more machines as needed
      # "mac-studio" = nix-darwin.lib.darwinSystem {
      #   modules = [
      #     ./machines/mac-studio/configuration.nix
      #     home-manager.darwinModules.home-manager
      #     {
      #       home-manager = {
      #         useGlobalPkgs = true;
      #         useUserPackages = true;
      #         users.jsp = import ./machines/mac-studio/home.nix;
      #       };
      #     }
      #   ];
      # };
    };
  };
}
