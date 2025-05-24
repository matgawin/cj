{
  description = "Personal Journal Management System";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = {
    self,
    nixpkgs,
    flake-utils,
    ...
  }:
    (flake-utils.lib.eachDefaultSystem (
      system: let
        pkgs = import nixpkgs {inherit system;};

        journal-management = import ./nix/package.nix {
          inherit pkgs;
          inherit self;
        };
      in {
        apps = import ./nix/apps.nix {
          inherit journal-management;
        };

        devShells = import ./nix/shell.nix {inherit pkgs;};

        packages = {
          inherit journal-management;
          default = journal-management;
        };
      }
    ))
    // {
      homeManagerModule.default = import ./nix/home-manager.nix {inherit self;};

      overlays.default = final: prev: {
        journal-management = self.packages.${prev.system}.default;
      };

      templates.default = {
        path = ./.;
        description = "Journal management system with automatic timestamp updates and nixos support.";
      };
    };
}
