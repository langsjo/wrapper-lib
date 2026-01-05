let
  fix = f: let x = f x; in x;
in
fix (self: {
  mkWrapper =
    pkgs: definition:
    let
      lib = pkgs.lib;
      module = pkgs.callPackage definition { };
      sanitizedModule = removeAttrs module [
        "override"
        "overrideDerivation"
      ];
    in
    (lib.evalModules {
      modules = [
        sanitizedModule
        ./wrapper-module.nix
        { _module.args = { inherit pkgs lib; }; }
      ];
    }).config.result
    // {
      override = args: self.mkWrapper (_: pkgs.callPackage definition args);
    };
})
