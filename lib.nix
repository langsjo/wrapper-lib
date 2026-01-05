let
  fix =
    f:
    let
      x = f x;
    in
    x;
  importIfPath = val: if builtins.isPath val then import val else val;
in
fix (self: {
  mkWrapper =
    pkgs: definition:
    let
      lib = pkgs.lib;
      module = importIfPath definition { };
    in
    (lib.evalModules {
      modules = [
        module
        ./wrapper-module.nix
        { _module.args = { inherit pkgs lib; }; }
      ];
    }).config.result.overrideAttrs
      (old: {
        passthru = old.passthru or { } // {
          override = args: self.mkWrapper pkgs (_: importIfPath definition args);
        };
      });
})
