{self}: {
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.services.journal-management;
in {
  options.services.journal-management = {
    enable = lib.mkEnableOption "journal management system";

    package = lib.mkOption {
      type = lib.types.package;
      default = self.packages.${pkgs.system}.default;
      description = "The journal management package to use.";
    };

    enableTimestampMonitor = lib.mkEnableOption "journal timestamp monitor service";

    enableAutoCreation = lib.mkEnableOption "automatic daily journal creation";

    journalDirectory = lib.mkOption {
      type = lib.types.str;
      default = "${config.home.homeDirectory}/Journal";
      description = "Directory where journal entries are stored.";
    };

    autoCreationTime = lib.mkOption {
      type = lib.types.str;
      default = "22:00";
      description = "Time to create journal entries (HH:MM format)";
      example = "09:00";
    };
  };

  config = lib.mkIf cfg.enable {
    home.packages = [cfg.package];

    systemd.user.services = lib.mkMerge [
      (lib.mkIf cfg.enableTimestampMonitor {
        journal-timestamp-monitor = {
          Unit = {
            Description = "Journal Timestamp Monitor Service";
            After = ["graphical-session.target"];
          };
          Service = {
            Type = "simple";
            ExecStart = "${cfg.package}/bin/journal-timestamp-monitor ${cfg.journalDirectory}";
            Restart = "on-failure";
            RestartSec = "5s";
            WorkingDirectory = cfg.journalDirectory;
          };
          Install.WantedBy = ["default.target"];
        };
      })

      (lib.mkIf cfg.enableAutoCreation {
        journal-auto-create = {
          Unit.Description = "Create Daily Journal Entry";
          Service = {
            Type = "oneshot";
            ExecStart = "${cfg.package}/bin/cj -d ${cfg.journalDirectory} -q";
            WorkingDirectory = cfg.journalDirectory;
          };
        };
      })
    ];

    systemd.user.timers = lib.mkIf cfg.enableAutoCreation {
      journal-auto-create = {
        Unit.Description = "Daily Journal Entry Creation";
        Timer = {
          OnCalendar = "*-*-* ${cfg.autoCreationTime}:00";
          Persistent = true;
        };
        Install.WantedBy = ["timers.target"];
      };
    };
  };
}
