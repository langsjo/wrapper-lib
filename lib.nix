let
  fix =
    f:
    let
      x = f x;
    in
    x;
in
fix (
  selfUninit:
  {
    useBinaryWrapper ? false,
  }:
  fix (selfInit: {
    withSettings = settings: selfUninit settings;
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
            useBinaryWrapper = lib.mkDefault useBinaryWrapper;
          }
        ];
      }).config.result.overrideAttrs
        (old: {
          passthru = old.passthru or { } // {
            override = args: selfInit.mkWrapper pkgs (_: pkgs.callPackage definition args);
          };
        });
  })
)
