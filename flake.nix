{
  description = "Personal Journal Management System";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
    systems.url = "github:nix-systems/default";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = {
    self,
    nixpkgs,
    flake-utils,
    ...
  }:
    flake-utils.lib.eachDefaultSystem (
      system: let
        pkgs = import nixpkgs {inherit system;};

        common = import ./nix/default.nix {inherit system pkgs;};

        packages = import ./nix/packages/default.nix {
          inherit self system pkgs;
          commonDeps = common.commonDeps;
        };

        apps = import ./nix/apps.nix {inherit self system pkgs;};

        legacyPackages = import ./nix/legacy-packages.nix {inherit self system pkgs;};

        devShells = {
          default = import ./nix/devShell.nix {
            inherit pkgs;
            devDeps = common.devDeps;
          };
        };
      in {
        inherit packages apps legacyPackages devShells;

        nixosModules.default = import ./nix/modules/nixos.nix {inherit self;};
        homeManagerModules.default = import ./nix/modules/home-manager.nix {inherit self;};
      }
    )
    // {
      overlays.default = final: prev: {
        journal-management = self.packages.${prev.system}.default;
      };

      templates.default = {
        path = ./.;
        description = "Journal management system with automatic timestamp updates";
      };
    };
}
