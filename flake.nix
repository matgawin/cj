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
        packages = {
          default = journal-management;
          journal-management = journal-management;
        };

        apps = import ./nix/apps.nix {
          inherit journal-management;
        };

        devShells.default = pkgs.mkShell {
          buildInputs = with pkgs; [
            bash
            shellcheck
            inotify-tools
            coreutils
            findutils
            gnugrep
            gnused
            gawk
            systemd
            gnumake
          ];
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
