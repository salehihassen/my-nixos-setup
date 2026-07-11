{
  description = "NixOS configs";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

    noctalia = {
      url = "github:noctalia-dev/noctalia-shell";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    compose2nix = {
      url = "github:aksiksi/compose2nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    zen-browser = {
      url = "github:0xc000022070/zen-browser-flake";
      inputs = {
        nixpkgs.follows = "nixpkgs";
        home-manager.follows = "home-manager";
      };
    };
  };

  outputs = inputs@{
    self,
    nixpkgs,
    home-manager,
    ...
  }:
  let
    system = "x86_64-linux";

    mkHostFor = { hostModule, username ? "saleh" }:
      nixpkgs.lib.nixosSystem {
        inherit system;

        specialArgs = {
          inherit inputs username;
        };

        modules = [
          ./configuration.nix
          hostModule

          home-manager.nixosModules.home-manager
          {
            home-manager.useGlobalPkgs = true;
            home-manager.useUserPackages = true;

            home-manager.extraSpecialArgs = {
              inherit inputs username;
            };

            home-manager.users.${username} = import ./home.nix;
          }
        ];
      };

    mkHost = hostModule:
      mkHostFor {
        inherit hostModule;
      };

    recoveryIso = nixpkgs.lib.nixosSystem {
      inherit system;

      specialArgs = {
        inherit inputs self;
      };

      modules = [
        ./iso/recovery.nix
      ];
    };
  in {
    nixosConfigurations = {
      j2 = mkHost ./hosts/j2.nix;
      b1 = mkHost ./hosts/b1.nix;
    };

    packages.${system}.recoveryIso = recoveryIso.config.system.build.isoImage;
  };
}
