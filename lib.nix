let
  fix =
    f:
    let
      x = f x;
    in
    x;
in
fix (
  self:
  {
    useBinaryWrapper ? false,
  }:
  {
    withSettings = settings: self settings;
    mkWrapper =
      pkgs: definition:
      let
        lib = pkgs.lib;
        module = pkgs.callPackage definition { };

        # callPackage adds these two attributes that aren't valid
        # module options
        sanitizedModule = builtins.removeAttrs module [
          "override"
          "overrideDerivation"
        ];
      in
      (lib.evalModules {
        modules = [
          sanitizedModule
          ./wrapper-module.nix
          { _module.args = { inherit pkgs lib; }; }

          {
            inherit useBinaryWrapper;
          }
        ];
      }).config.result.overrideAttrs
        (old: {
          passthru = old.passthru or { } // {
            override = args: self.mkWrapper pkgs (_: pkgs.callPackage definition args);
          };
        });
  }
)
