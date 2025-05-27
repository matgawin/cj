{
  description = "Personal Journal Management System";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
    flake-parts.url = "github:hercules-ci/flake-parts";
  };

  outputs = inputs @ {flake-parts, ...}:
    flake-parts.lib.mkFlake {inherit inputs;} {
      systems = ["x86_64-linux" "aarch64-linux"];
      perSystem = {pkgs, ...}: let
        journal-management = import ./nix/package.nix {
          inherit pkgs;
          inherit (inputs) self;
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
      };
      flake = with inputs; {
        homeManagerModule.default = import ./nix/home-manager.nix {inherit self;};

        overlays.default = _: prev: {
          journal-management = self.packages.${prev.system}.default;
        };

        templates.default = {
          path = ./.;
          description = "Journal management system with automatic timestamp updates and nixos support.";
        };
      };
    };
}
