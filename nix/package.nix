{
  self,
  pkgs,
  ...
}:
pkgs.stdenv.mkDerivation rec {
  pname = "journal-management";
  version = "1.1.0";
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

  installPhase = with pkgs; ''
    runHook preInstall

    mkdir -p $out/bin $out/share/journal

    cp src/lib/common.sh $out/share/journal/common.sh
    cp src/lib/error_handling.sh $out/share/journal/error_handling.sh
    cp src/lib/sops_utils.sh $out/share/journal/sops_utils.sh

    cp src/bin/create_journal_entry.sh $out/bin/cj
    cp src/bin/journal_timestamp_monitor.sh $out/bin/journal-timestamp-monitor

    chmod +x $out/bin/cj
    chmod +x $out/bin/journal-timestamp-monitor

    substituteInPlace $out/bin/cj \
        --replace '#!/usr/bin/env bash' '#!${bash}/bin/bash'

    substituteInPlace $out/bin/journal-timestamp-monitor \
        --replace '#!/usr/bin/env bash' '#!${bash}/bin/bash'

    substituteInPlace $out/share/journal/common.sh \
        --replace '#!/usr/bin/env bash' '#!${bash}/bin/bash'

    substituteInPlace $out/share/journal/error_handling.sh \
        --replace '#!/usr/bin/env bash' '#!${bash}/bin/bash'

    substituteInPlace $out/share/journal/sops_utils.sh \
        --replace '#!/usr/bin/env bash' '#!${bash}/bin/bash'

    substituteInPlace $out/bin/cj \
        --replace 'COMMON_LIB="''${SCRIPT_DIR}/../lib/common.sh"' \
                'COMMON_LIB="'"$out/share/journal/common.sh"'"' \
        --replace 'ERROR_LIB="''${SCRIPT_DIR}/../lib/error_handling.sh"' \
                'ERROR_LIB="'"$out/share/journal/error_handling.sh"'"' \
        --replace 'SOPS_LIB="''${SCRIPT_DIR}/../lib/sops_utils.sh"' \
                'SOPS_LIB="'"$out/share/journal/sops_utils.sh"'"'

    substituteInPlace $out/bin/journal-timestamp-monitor \
        --replace 'COMMON_LIB="''${SCRIPT_DIR}/../lib/common.sh"' \
                'COMMON_LIB="'"$out/share/journal/common.sh"'"' \
        --replace 'SOPS_LIB="''${SCRIPT_DIR}/../lib/sops_utils.sh"' \
                'SOPS_LIB="'"$out/share/journal/sops_utils.sh"'"'

    wrapProgram $out/bin/cj \
        --prefix PATH : ${lib.makeBinPath buildInputs}

    wrapProgram $out/bin/journal-timestamp-monitor \
        --prefix PATH : ${lib.makeBinPath buildInputs}

    runHook postInstall
  '';

  meta = with pkgs.lib; {
    description = "Journal management system with automatic timestamp updates and nixos support.";
    homepage = "https://github.com/matgawin/cj";
    license = licenses.mit;
    platforms = platforms.unix;
    maintainers = [];
  };
}
