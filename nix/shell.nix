{pkgs ? import <nixpkgs> {}, ...}: {
  default = pkgs.mkShell {
    buildInputs = with pkgs; [
      bash
      coreutils
      deadnix
      fd
      gnumake
      gnused
      inotify-tools
      jujutsu
      shellcheck
      statix
      sops
      systemd
    ];

    shellHook = ''
      echo "Welcome to the Journal Management System development shell!";
    '';
  };
}
