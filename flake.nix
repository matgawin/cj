{
  description = "Personal Journal Management System";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
    flake-utils = {
      url = "github:numtide/flake-utils";
      inputs.nixpkgs.follows = "nixpkgs";
    };
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
        inherit (pkgs) lib;

        journal-management = pkgs.stdenv.mkDerivation rec {
          pname = "journal-management";
          version = "0.1.0";
          src = self;

          nativeBuildInputs = with pkgs; [
            makeWrapper
          ];

          buildInputs = with pkgs; [
            bash
            coreutils
            findutils
            gnugrep
            gnused
            gawk
            systemd
            inotify-tools
          ];

          dontBuild = true;

          installPhase = ''
            runHook preInstall

            mkdir -p $out/bin $out/share/journal

            cp src/lib/common.sh $out/share/journal/common.sh

            cp src/bin/create_journal_entry.sh $out/bin/cj
            cp src/bin/journal_timestamp_monitor.sh $out/bin/journal-timestamp-monitor

            chmod +x $out/bin/cj
            chmod +x $out/bin/journal-timestamp-monitor

            substituteInPlace $out/bin/cj \
              --replace '#!/bin/bash' '#!${pkgs.bash}/bin/bash'

            substituteInPlace $out/bin/journal-timestamp-monitor \
              --replace '#!/bin/bash' '#!${pkgs.bash}/bin/bash'

            substituteInPlace $out/share/journal/common.sh \
              --replace '#!/bin/bash' '#!${pkgs.bash}/bin/bash'

            substituteInPlace $out/bin/cj \
              --replace 'COMMON_LIB="''${SCRIPT_DIR}/../lib/common.sh"' \
                        'COMMON_LIB="'"$out/share/journal/common.sh"'"'

            substituteInPlace $out/bin/journal-timestamp-monitor \
              --replace 'COMMON_LIB="''${SCRIPT_DIR}/../lib/common.sh"' \
                        'COMMON_LIB="'"$out/share/journal/common.sh"'"'

            wrapProgram $out/bin/cj \
              --prefix PATH : ${lib.makeBinPath buildInputs}

            wrapProgram $out/bin/journal-timestamp-monitor \
              --prefix PATH : ${lib.makeBinPath buildInputs}

            runHook postInstall
          '';

          meta = with pkgs.lib; {
            description = "Journal management system with automatic timestamp updates and nixos support.";
            homepage = "";
            license = licenses.mit;
            platforms = platforms.unix;
            maintainers = [];
          };
        };
      in {
        packages = {
          default = journal-management;
          journal-management = journal-management;
        };

        apps = {
          default = {
            type = "app";
            program = "${journal-management}/bin/cj";
          };
          cj = {
            type = "app";
            program = "${journal-management}/bin/cj";
          };
          journal-timestamp-monitor = {
            type = "app";
            program = "${journal-management}/bin/journal-timestamp-monitor";
          };
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
