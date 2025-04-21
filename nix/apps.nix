{
  self,
  system,
}: rec {
  cj = {
    type = "app";
    program = "${self.packages.${system}.default}/bin/cj";
  };
  default = cj;
}
