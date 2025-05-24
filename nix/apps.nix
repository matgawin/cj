{journal-management}: {
  default = {
    type = "app";
    program = "${journal-management}/bin/cj";
  };
  cj = {
    type = "app";
    program = "${journal-management}/bin/cj";
  };
  journal-timestamp-monitor = {
    type = "app";
    program = "${journal-management}/bin/journal-timestamp-monitor";
  };
}
