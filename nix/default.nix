{pkgs, ...}: {
  commonDeps = with pkgs; [
    bash
    coreutils
  ];

  devDeps = with pkgs; [
    bash
    shellcheck
    gnumake
  ];
}
