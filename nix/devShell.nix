{
  pkgs,
  devDeps,
}:
pkgs.mkShell {
  buildInputs = devDeps;
}
