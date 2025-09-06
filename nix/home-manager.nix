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
      inherit (self.packages.${pkgs.system}) default;
      type = lib.types.package;
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
      description = "Time at which to create journal entries (HH:MM format)";
      example = "09:00";
    };

    startDate = lib.mkOption {
      type = lib.types.str;
      default = "2022-10-21";
      description = "Start date for the journal entries in YYYY-MM-DD format. Used for day counting.";
      example = "2023-01-01";
    };

    sopsConfig = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      description = "Path to SOPS configuration file for encrypted journal entries. If null, auto-detection will be used.";
      example = "${config.home.homeDirectory}/Journal/.sops.yaml";
    };

    enableSopsSupport = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Enable SOPS encryption support for journal services. Requires sops to be available in PATH.";
    };

    sopsAgeKeyFile = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      description = "Path to Age private key file for SOPS decryption. If null, defaults to SOPS_AGE_KEY_FILE environment variable or ~/.config/sops/age/keys.txt";
      example = "${config.home.homeDirectory}/.config/sops/age/keys.txt";
    };
  };

  config = lib.mkIf cfg.enable {
    home.packages = [cfg.package];

    home.file.".config/cj/start_date".text = cfg.startDate;

    systemd.user.services = lib.mkMerge [
      (lib.mkIf cfg.enableTimestampMonitor {
        journal-timestamp-monitor = {
          Unit = {
            Description = "Journal Timestamp Monitor Service (with encryption support)";
            After = ["graphical-session.target"];
          };
          Service = {
            Type = "simple";
            ExecStart = "${cfg.package}/bin/journal-timestamp-monitor ${cfg.journalDirectory}";
            Restart = "on-failure";
            RestartSec = "5s";
            WorkingDirectory = cfg.journalDirectory;
          } // lib.optionalAttrs cfg.enableSopsSupport {
            Environment = [] 
              ++ lib.optionals (cfg.sopsConfig != null) ["SOPS_CONFIG_PATH=${cfg.sopsConfig}"]
              ++ lib.optionals (cfg.sopsAgeKeyFile != null) ["SOPS_AGE_KEY_FILE=${cfg.sopsAgeKeyFile}"];
          };
          Install.WantedBy = ["default.target"];
        };
      })

      (lib.mkIf cfg.enableAutoCreation {
        journal-auto-create = {
          Unit.Description = "Create Daily Journal Entry (with encryption support)";
          Service = {
            Type = "oneshot";
            ExecStart = "${cfg.package}/bin/cj -d ${cfg.journalDirectory} -q";
            WorkingDirectory = cfg.journalDirectory;
          } // lib.optionalAttrs cfg.enableSopsSupport {
            Environment = [] 
              ++ lib.optionals (cfg.sopsConfig != null) ["SOPS_CONFIG_PATH=${cfg.sopsConfig}"]
              ++ lib.optionals (cfg.sopsAgeKeyFile != null) ["SOPS_AGE_KEY_FILE=${cfg.sopsAgeKeyFile}"];
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
