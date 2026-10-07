{
  description = "NixOS configs";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

    # Keep the nightly source build's toolchain pinned by its packaging flake.
    # Update this input independently with: nix flake update t3-code-nix
    t3-code-nix.url = "github:LisaScheers/t3-code-nix";

    noctalia = {
      url = "github:noctalia-dev/noctalia";
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

    displaylinkSrc = {
      url = "github:salehihassen/nixpkgs/edd273db0c3211fabdc6b646ff3abd73c90ef7b3";
      flake = false;
    };
  };

  outputs =
    inputs@{
      self,
      nixpkgs,
      home-manager,
      ...
    }:
    let
      system = "x86_64-linux";

      mkHostFor =
        {
          hostModule,
          homeModules ? [ ./home/portable.nix ],
          username ? "saleh",
          dotfilesRoot ? "/etc/nixos",
        }:
        nixpkgs.lib.nixosSystem {
          inherit system;

          specialArgs = {
            inherit inputs username dotfilesRoot;
          };

          modules = [
            ./configuration.nix
            hostModule

            home-manager.nixosModules.home-manager
            {
              home-manager.useGlobalPkgs = true;
              home-manager.useUserPackages = true;

              home-manager.extraSpecialArgs = {
                inherit inputs username dotfilesRoot;
              };

              home-manager.users.${username}.imports = homeModules;
            }
          ];
        };

      mkHost =
        hostModule:
        mkHostFor {
          inherit hostModule;
        };

      mkStandaloneHome =
        {
          username,
          homeDirectory,
          dotfilesRoot,
          system ? "x86_64-linux",
          homeModules ? [ ],
        }:
        home-manager.lib.homeManagerConfiguration {
          pkgs = nixpkgs.legacyPackages.${system};

          extraSpecialArgs = {
            inherit
              inputs
              username
              homeDirectory
              dotfilesRoot
              ;
          };

          modules = [
            ./home/portable.nix
            {
              home.homeDirectory = homeDirectory;
              targets.genericLinux.enable = true;
            }
          ]
          ++ homeModules;
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
    in
    {
      lib.mkStandaloneHome = mkStandaloneHome;
      homeModules.portable = ./home/portable.nix;
      homeModules.desktop = ./home/desktop.nix;
      homeModules.snapshot-work = ./home/snapshot-work.nix;
      homeModules.av-editor = ./home/av-editor.nix;
      homeModules.hardware-design = ./home/hardware-design.nix;
      homeModules.desktop-control = ./home/desktop-control.nix;

      nixosModules.desktop-control = ./modules/desktop-control.nix;

      nixosConfigurations = {
        j2 = mkHostFor {
          hostModule = ./hosts/j2.nix;
          homeModules = [
            ./home/portable.nix
            ./home/desktop.nix
            ./home/snapshot-work.nix
            ./home/av-editor.nix
            ./home/hardware-design.nix
            ./home/desktop-control.nix
            ./home/j2.nix
          ];
        };
        b1 = mkHost ./hosts/b1.nix;
      };

      packages.${system}.recoveryIso = recoveryIso.config.system.build.isoImage;

      checks.${system} =
        let
          pkgs = nixpkgs.legacyPackages.${system};
          standalone =
            homeModules:
            mkStandaloneHome {
              inherit homeModules;
              username = "portable";
              homeDirectory = "/home/portable";
              dotfilesRoot = "/opt/dotfiles";
            };
          snapshotCommand =
            sourceMode:
            (home-manager.lib.homeManagerConfiguration {
              inherit pkgs;
              extraSpecialArgs.dotfilesRoot = "/build/editable checkout";
              modules = [
                ./home/snapshot-work.nix
                {
                  home.username = "test";
                  home.homeDirectory = "/home/test";
                  home.stateVersion = "25.11";
                  programs.snapshot-work.sourceMode = sourceMode;
                }
              ];
            }).config.home.file.".local/bin/capture-work".source;
        in
        {
          portable-home = (standalone [ ]).activationPackage;
          desktop-home = (standalone [ ./home/desktop.nix ]).activationPackage;
          snapshot-home =
            (standalone [
              ./home/desktop.nix
              ./home/snapshot-work.nix
            ]).activationPackage;
          snapshot-tests =
            pkgs.runCommand "snapshot-work-tests" { nativeBuildInputs = [ pkgs.nodejs_24 ]; }
              ''
                node --test ${./scripts/snapshot-work}/capture.test.mjs
                touch "$out"
              '';
          snapshot-wrappers = pkgs.runCommand "snapshot-work-wrappers" { } ''
            ${snapshotCommand "store"} --help > help.txt
            grep -q 'default 5000' help.txt
            mkdir -p '/build/editable checkout/scripts/snapshot-work'
            script='/build/editable checkout/scripts/snapshot-work/capture.mjs'
            printf 'console.log(JSON.stringify(process.argv.slice(2)));\n' > "$script"
            ${snapshotCommand "checkout"} 'one two' three > actual.txt
            printf '["one two","three"]\n' > expected.txt
            cmp actual.txt expected.txt
            printf 'console.log("edited");\n' > "$script"
            ${snapshotCommand "checkout"} > actual.txt
            grep -qx edited actual.txt
            rm "$script"
            if ${snapshotCommand "checkout"} > missing.txt 2>&1; then
              echo 'Missing checkout should fail' >&2
              exit 1
            fi
            grep -q 'Capture script is missing' missing.txt
            touch "$out"
          '';
        };
    };
}
