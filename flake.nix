{
  description = "j2 Niri + Noctalia daily driver";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

    noctalia = {
      url = "github:noctalia-dev/noctalia-shell";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };
  
  outputs = inputs@{ self, nixpkgs, noctalia, ... }:
    let
      system = "x86_64-linux";
    in {
      nixosConfigurations.j2 = nixpkgs.lib.nixosSystem {
        inherit system;
        specialArgs = { inherit inputs; };

        modules = [
          ./configuration.nix
        ];
      };
    }; 
}
