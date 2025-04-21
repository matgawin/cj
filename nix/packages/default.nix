{
  self,
  pkgs,
  commonDeps,
}: rec {
  journal-management = pkgs.stdenv.mkDerivation {
    pname = "journal-management";
    version = "0.1.0";
    src = self;

    buildInputs = commonDeps;

    buildPhase = '''';

    installPhase = ''
      mkdir -p $out/bin

      cp src/bin/create_journal_entry.sh $out/bin/cj
      chmod +x $out/bin/cj

      cp src/bin/journal_timestamp_monitor.sh $out/bin/journal-timestamp-monitor
      chmod +x $out/bin/journal-timestamp-monitor
    '';

    meta = with pkgs.lib; {
      description = "Journal management system with automatic timestamp updates";
      license = licenses.mit;
      platforms = platforms.all;
      maintainers = [];
    };
  };

  default = journal-management;
  cj = journal-management;
}
