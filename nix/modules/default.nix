{self, ...}: {
  nixosModule = import ./common.nix {
    inherit self;
    isNixOS = true;
  };
  homeManagerModule = import ./common.nix {
    inherit self;
    isNixOS = false;
  };
}
