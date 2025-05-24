{pkgs ? import <nixpkgs> {}, ...}: {
  default = pkgs.mkShell {
    buildInputs = with pkgs; [
      bash
      coreutils
      fd
      gnumake
      gnused
      inotify-tools
      jujutsu
      shellcheck
      systemd
    ];
    shellHook = ''
      echo "Welcome to the Journal Management System development shell!";
    '';
  };
}
