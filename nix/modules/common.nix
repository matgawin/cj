{
  self,
  isNixOS ? false,
}: {
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.services.journal-management;
  userHome =
    if isNixOS
    then "${config.users.users.${cfg.user}.home}"
    else "${config.home.homeDirectory}";
in {
  options.services.journal-management =
    {
      enable = lib.mkEnableOption "journal management system";

      package = lib.mkOption {
        type = lib.types.package;
        default = self.packages.${pkgs.system}.default;
        description = "The journal management package to use.";
      };

      enableTimestampMonitor = lib.mkEnableOption "journal timestamp monitor service";

      journalDirectory = lib.mkOption {
        type = lib.types.str;
        default = "${userHome}/Journal";
        description = "Directory where journal entries are stored.";
      };

      enableAutoCreation = lib.mkEnableOption "automatic daily journal creation";

      autoCreationTime = lib.mkOption {
        type = lib.types.str;
        default = "22:00";
        description = "Time to create journal entries (HH:MM format)";
      };
    }
    // (
      if isNixOS
      then {
        user = lib.mkOption {
          type = lib.types.str;
          default = "nobody";
          description = "User account under which the services run.";
        };
      }
      else {}
    );

  config = lib.mkIf cfg.enable {
    ${
      if isNixOS
      then "environment"
      else "home"
    }.packages = [cfg.package];

    systemd = let
      monitorService = {
        description = "Journal Timestamp Monitor Service";
        wantedBy = ["default.target"];
        after = ["network.target"];
        path = [cfg.package];
        serviceConfig = {
          Type = "simple";
          ExecStart = "${cfg.package}/bin/journal-timestamp-monitor ${cfg.journalDirectory}";
          Restart = "on-failure";
          RestartSec = "5s";
        };
      };

      autoCreationTimer = {
        description = "Daily Journal Entry Creation";
        wantedBy = ["timers.target"];
        timerConfig = {
          OnCalendar = "*-*-* ${cfg.autoCreationTime}:00";
          Persistent = true;
          Unit = "journal-auto-create.service";
        };
      };

      autoCreationService = {
        description = "Create Daily Journal Entry";
        path = [cfg.package];
        serviceConfig = {
          Type = "oneshot";
          ExecStart = "${cfg.package}/bin/cj -d ${cfg.journalDirectory} -q";
        };
      };
    in {
      ${
        if isNixOS
        then "services"
        else "user.services"
      } = lib.mkMerge [
        (lib.mkIf cfg.enableTimestampMonitor {
          "journal-timestamp-monitor" =
            if isNixOS
            then monitorService
            else {
              Unit = {
                Description = monitorService.description;
                After = monitorService.after;
              };
              Service = monitorService.serviceConfig;
              Install = {
                WantedBy = monitorService.wantedBy;
              };
            };
        })

        (lib.mkIf cfg.enableAutoCreation {
          "journal-auto-create" =
            if isNixOS
            then autoCreationService
            else {
              Unit = {Description = autoCreationService.description;};
              Service = autoCreationService.serviceConfig;
            };
        })
      ];

      ${
        if isNixOS
        then "timers"
        else "user.timers"
      } = lib.mkIf cfg.enableAutoCreation {
        "journal-auto-create" =
          if isNixOS
          then autoCreationTimer
          else {
            Unit = {Description = autoCreationTimer.description;};
            Timer = autoCreationTimer.timerConfig;
            Install = {WantedBy = autoCreationTimer.wantedBy;};
          };
      };
    };
  };
}
