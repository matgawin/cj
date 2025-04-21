{
  self,
  system,
  pkgs,
}: {
  inherit (self.packages.${system}) default;

  installScript = pkgs.writeScriptBin "install-journal-management" ''
    #!/bin/bash
    SCRIPT_DIR="${builtins.toString self}"
    exec "$SCRIPT_DIR/scripts/install.sh" "$@"
  '';

  uninstallScript = pkgs.writeScriptBin "uninstall-journal-management" ''
    #!/bin/bash
    SCRIPT_DIR="${builtins.toString self}"
    exec "$SCRIPT_DIR/scripts/uninstall.sh" "$@"
  '';
}
